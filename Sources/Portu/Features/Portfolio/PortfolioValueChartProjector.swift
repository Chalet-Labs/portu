import Foundation
import os
import PortuCore
import SwiftData

// swiftformat:disable redundantSendable

/// One `PortfolioSnapshot` as the value chart draws it, in USD.
struct PortfolioValueSnapshotPoint: Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let totalValueUSD: Decimal
    let isPartial: Bool
}

/// The value chart's month in USD, built off the main actor by `PortfolioValueChartProjector`
/// (#124, spec C1). It holds no model and no display currency: the rates cover every quote
/// currency, so a currency switch converts it again without a rebuild.
struct PortfolioValueChartSource: Equatable, Sendable {
    /// The month's snapshots, sorted by timestamp.
    var snapshots: [PortfolioValueSnapshotPoint]
    /// The month's rate rows, for every quote currency, sorted by day.
    var rates: [CurrencyConversionRateEntry]
    /// The estimated segment before the first recorded point; empty with backfill off.
    var estimatedUSD: [HistoricalPortfolioValuePoint]

    static let empty = PortfolioValueChartSource(snapshots: [], rates: [], estimatedUSD: [])
}

/// Builds the `PortfolioValueChartSource` from the store, off the main actor (#124, spec C1, C2).
///
/// Its own actor and model context, not the holdings projector's: the estimate's first-day
/// `AssetSnapshot` fetch can materialise a whole sync day (~12k rows at ~500 assets × 24 syncs/day,
/// #97), and a holdings build must never wait behind it. Read-only: it never inserts, changes or
/// saves.
@ModelActor
actor PortfolioValueChartProjector {
    private static let logger = Logger(subsystem: "com.portu.app", category: "PortfolioReadModel")

    /// The entities a build reads. A save touching none of them can't change the chart.
    static let readEntityNames: Set<String> = [
        "PortfolioSnapshot",
        "CurrencyConversionRatePoint",
        "AssetSnapshot",
        "HistoricalPricePoint",
        "TokenPricingOverride",
        "Asset"
    ]

    /// A failed snapshot or rate fetch fails the build, so the reducer keeps the chart it has
    /// instead of drawing an empty or wrongly converted month. A failed estimate fetch yields no
    /// estimate, as the chart's `try?` did.
    func build(_ request: PortfolioProjectionRequest) throws -> PortfolioValueChartSource {
        // A build cancelled while it waited behind another reads nothing.
        try Task.checkCancellation()
        let interval = PortfolioTimings.beginValueChartBuild()
        var completed = false
        // Every path ends the signpost; only a completed build is the "latest" duration.
        defer { PortfolioTimings.endValueChartBuild(interval, completed: completed) }

        let chartStart = ChartTimeRange.oneMonth.startDate(at: request.now)
        let chartStartDay = HistoricalPriceCalendar.utcStartOfDay(for: chartStart)
        let snapshots = try modelContext.fetch(FetchDescriptor<PortfolioSnapshot>(
            predicate: #Predicate<PortfolioSnapshot> { $0.timestamp >= chartStart },
            sortBy: [SortDescriptor(\.timestamp)]))
        try Task.checkCancellation()
        // Every quote currency, so a currency switch needs no rebuild; sorted by day as the
        // chart's query was.
        let rates = try modelContext.fetch(FetchDescriptor<CurrencyConversionRatePoint>(
            predicate: #Predicate<CurrencyConversionRatePoint> { $0.day >= chartStartDay },
            sortBy: [SortDescriptor(\.day)]))
        try Task.checkCancellation()
        let estimatedUSD = try request.isHistoricalBackfillEnabled ? estimatedSegment(chartStart: chartStart) : []

        let source = PortfolioValueChartSource(
            snapshots: snapshots.map { snapshot in
                PortfolioValueSnapshotPoint(
                    id: snapshot.id,
                    timestamp: snapshot.timestamp,
                    totalValueUSD: snapshot.totalValue,
                    isPartial: snapshot.isPartial)
            },
            rates: rates.map(CurrencyConversionRateEntry.init),
            estimatedUSD: estimatedUSD)
        completed = true
        return source
    }

    /// The estimated segment, which only backfill draws. The price fetch reads only the USD closes
    /// `PortfolioValueChartFeature.estimatedPoints` keeps, `[chartStartDay, firstRealSnapshotDate)`,
    /// and only once there is an estimate to price. A failed fetch draws no estimate rather than a
    /// wrong one (with ignored assets, or unpriced), and is logged.
    private func estimatedSegment(chartStart: Date) throws -> [HistoricalPortfolioValuePoint] {
        let overrides: [TokenPricingOverride]
        do {
            overrides = try modelContext.fetch(FetchDescriptor<TokenPricingOverride>())
        } catch {
            Self.logger.error("Value chart estimate skipped, overrides fetch failed: \(String(describing: error), privacy: .public)")
            return []
        }
        try Task.checkCancellation()
        let source = estimateSource(overrides: overrides.map(TokenPricingOverrideSnapshot.init), chartStartDate: chartStart)
        guard let source else { return [] }
        try Task.checkCancellation()

        let chartStartDay = HistoricalPriceCalendar.utcStartOfDay(for: chartStart)
        let firstRealSnapshotDate = source.firstRealSnapshotDate
        let rows: [HistoricalPricePoint]
        do {
            rows = try modelContext.fetch(FetchDescriptor<HistoricalPricePoint>(
                predicate: #Predicate<HistoricalPricePoint> { $0.day >= chartStartDay && $0.day < firstRealSnapshotDate },
                sortBy: [SortDescriptor(\.day)]))
        } catch {
            Self.logger.error("Value chart estimate skipped, price fetch failed: \(String(describing: error), privacy: .public)")
            return []
        }
        let prices = rows.compactMap { row -> HistoricalPriceEntry? in
            guard row.fiatCurrency == .usd else { return nil }
            return HistoricalPriceEntry(coinGeckoId: row.coinGeckoId, day: row.day, usdPrice: row.usdPrice)
        }
        return PortfolioValueChartFeature.estimatedPoints(
            source: source,
            prices: prices,
            chartStartDate: chartStart,
            isBackfillEnabled: true)
    }

    /// Returns the estimate source, or `nil` when no backfill is possible.
    ///
    /// Steps: (1) limit-1 earliest row probe; (2) limit-1 earliest PortfolioSnapshot probe and
    /// parity guard; (3) single UTC-day fetch; (4) dedup by (accountId, assetId), keeping the
    /// earliest row per key; (5) targeted Asset fetch from winner ids only; (6) project to value
    /// types. `try?` on any AssetSnapshot fetch → nil; a failed PortfolioSnapshot probe only
    /// leaves the end where the holdings are. Both AssetSnapshot fetches leave out the assets
    /// ignored now, old rows included (N2).
    func estimateSource(
        overrides: [TokenPricingOverrideSnapshot],
        chartStartDate: Date) -> PortfolioValueChartEstimateSource? {
        let ignoredIDs = Array(TokenPricingOverrideFeature.ignoredAssetIds(overrides))

        // 1. Globally-earliest non-ignored AssetSnapshot — limit-1 fetch, no full table scan.
        var earliestDescriptor = FetchDescriptor<AssetSnapshot>(
            predicate: #Predicate<AssetSnapshot> { !ignoredIDs.contains($0.assetId) },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        earliestDescriptor.fetchLimit = 1
        guard let earliest = (try? modelContext.fetch(earliestDescriptor))?.first else { return nil }

        var recordedDescriptor = FetchDescriptor<PortfolioSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        recordedDescriptor.fetchLimit = 1
        let firstRecordedDate = (try? modelContext.fetch(recordedDescriptor))?.first?.timestamp
        let estimateEndDate = HistoricalPortfolioEstimator.estimateEndDate(
            holdingsDate: earliest.timestamp,
            firstRecordedDate: firstRecordedDate)

        // Parity guard: when the end < chartStart, the window [chartStartDay, utcStartOfDay(end))
        // is empty, so the estimator returns [].
        if estimateEndDate < chartStartDate {
            return nil
        }

        // 2. All rows on that single UTC day.
        let firstDay = HistoricalPriceCalendar.utcStartOfDay(for: earliest.timestamp)
        let dayEnd = firstDay.addingTimeInterval(24 * 60 * 60)
        let dayDescriptor = FetchDescriptor<AssetSnapshot>(
            predicate: #Predicate<AssetSnapshot> {
                $0.timestamp >= firstDay && $0.timestamp < dayEnd && !ignoredIDs.contains($0.assetId)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        guard let dayRows = try? modelContext.fetch(dayDescriptor) else { return nil }

        // 3. Dedup: keep only the earliest row per (accountId, assetId) key.
        //    dayRows is sorted ascending by timestamp, so the first occurrence per key is earliest.
        var seenKeys = Set<AssetSnapshotKey>()
        var winners: [AssetSnapshot] = []
        for row in dayRows
            where seenKeys.insert(AssetSnapshotKey(accountId: row.accountId, assetId: row.assetId)).inserted {
            winners.append(row)
        }

        // 4. Only the Asset rows referenced by the winners — never the full Asset table.
        let assetIDs = Array(Set(winners.map(\.assetId)))
        var assetsById: [UUID: Asset] = [:]
        if !assetIDs.isEmpty {
            let assetDescriptor = FetchDescriptor<Asset>(
                predicate: #Predicate<Asset> { assetIDs.contains($0.id) })
            if let assets = try? modelContext.fetch(assetDescriptor) {
                assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            }
        }

        // 5. Project winners to value types.
        let overridesByAssetId = TokenPricingOverrideFeature.overridesByAssetId(overrides)
        let entries: [HistoricalEstimateSnapshotEntry] = winners.map { snapshot in
            let asset = assetsById[snapshot.assetId]
            return HistoricalEstimateSnapshotEntry(
                accountId: snapshot.accountId,
                assetId: snapshot.assetId,
                timestamp: snapshot.timestamp,
                coinGeckoId: asset?.coinGeckoId,
                coinGeckoIdOverride: overridesByAssetId[snapshot.assetId]?.coinGeckoIdOverride,
                onchainIdentity: OnchainTokenIdentity(
                    chain: asset?.upsertChain,
                    contractAddress: asset?.upsertContract),
                amount: snapshot.amount,
                borrowAmount: snapshot.borrowAmount,
                netUSDValue: snapshot.usdValue - snapshot.borrowUsdValue)
        }

        return PortfolioValueChartEstimateSource(
            firstRealSnapshotDate: earliest.timestamp,
            firstDayEntries: entries,
            firstRecordedDate: firstRecordedDate)
    }

    #if DEBUG
        /// Regression probe for the creation-queue invariant of `PortfolioValueChartProjectorClient.live`.
        func isExecutingOnMainThread() -> Bool {
            Thread.isMainThread
        }

        /// Holds this actor's executor, as a long build would, until `release` is signalled. `onHold`
        /// runs once it is held. The probe for "a chart build held open doesn't delay a holdings
        /// build" (spec C2).
        func holdExecutor(until release: DispatchSemaphore, onHold: @Sendable () -> Void) {
            onHold()
            release.wait()
        }
    #endif
}

/// Flat dedup key for the first-day winner scan — same shape as
/// `PerformanceFeature.earliestEstimateSnapshots`'s `SnapshotKey`.
private struct AssetSnapshotKey: Hashable {
    let accountId: UUID
    let assetId: UUID
}
