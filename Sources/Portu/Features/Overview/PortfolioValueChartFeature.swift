// Sources/Portu/Features/Overview/PortfolioValueChartFeature.swift
import Foundation
import PortuCore
import SwiftData

/// Source data for the estimated pre-snapshot segment of the portfolio value chart.
/// Fetched from SwiftData at the model boundary so no live models escape into body.
struct PortfolioValueChartEstimateSource: Equatable, Sendable {
    /// Timestamp of the globally-earliest AssetSnapshot row.
    let firstRealSnapshotDate: Date
    /// Deduped value-type projections of the first-day AssetSnapshot rows —
    /// earliest per (accountId, assetId) key, matching `earliestEstimateHoldings` dedup.
    let firstDayEntries: [HistoricalEstimateSnapshotEntry]
}

/// Fetches the minimum `AssetSnapshot` rows required to back-fill the chart's estimated segment.
///
/// Running on a background `@ModelActor` keeps all row materialisation off the main thread.
/// A single sync day at the ~12k rows/day rate (#97 arithmetic: ~500 assets × 24 syncs/day)
/// can fill the entire table, so materialising the first-day fetch on the main thread causes a
/// Hang. Main receives only the small deduped value-type result.
@ModelActor
actor PortfolioValueChartEstimateFetcher {
    /// Returns the estimate source, or `nil` when no backfill is possible.
    ///
    /// Steps: (1) limit-1 earliest row probe; (2) parity guard; (3) single UTC-day fetch;
    /// (4) dedup by (accountId, assetId), keeping the earliest row per key; (5) targeted Asset
    /// fetch from winner ids only; (6) project to value types. `try?` on any fetch → nil.
    func estimateSource(
        overrides: [TokenPricingOverrideSnapshot],
        chartStartDate: Date) -> PortfolioValueChartEstimateSource? {
        // 1. Globally-earliest AssetSnapshot — limit-1 fetch, no full table scan.
        var earliestDescriptor = FetchDescriptor<AssetSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        earliestDescriptor.fetchLimit = 1
        guard let earliest = (try? modelContext.fetch(earliestDescriptor))?.first else { return nil }

        // Parity guard: when earliest < chartStart, the price window [chartStartDay, firstRealDay)
        // is empty (firstRealDay ≤ chartStart), so the estimator returns [].
        if earliest.timestamp < chartStartDate {
            return nil
        }

        // 2. All rows on that single UTC day.
        let firstDay = HistoricalPriceCalendar.utcStartOfDay(for: earliest.timestamp)
        let dayEnd = firstDay.addingTimeInterval(24 * 60 * 60)
        let dayDescriptor = FetchDescriptor<AssetSnapshot>(
            predicate: #Predicate<AssetSnapshot> {
                $0.timestamp >= firstDay && $0.timestamp < dayEnd
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
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(overrides)
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
            firstDayEntries: entries)
    }
}

/// Flat dedup key for the first-day winner scan — same shape as
/// `PerformanceFeature.earliestEstimateSnapshots`'s `SnapshotKey`.
private struct AssetSnapshotKey: Hashable {
    let accountId: UUID
    let assetId: UUID
}

enum PortfolioValueChartFeature {
    /// Pure estimate computation — no models in the signature; safe to call on the main actor
    /// from a `.task` closure without any blocking.
    ///
    /// The day-window filter (`>= chartStartDay`, `< firstRealSnapshotDate`) is applied here,
    /// preserving exact parity with the former `estimatedPoints` computed property.
    static func estimatedPoints(
        source: PortfolioValueChartEstimateSource,
        prices: [HistoricalPriceEntry],
        chartStartDate: Date,
        isBackfillEnabled: Bool) -> [HistoricalPortfolioValuePoint] {
        guard isBackfillEnabled else { return [] }

        let holdings = PerformanceFeature.earliestEstimateHoldings(
            snapshots: source.firstDayEntries,
            firstRealSnapshotDate: source.firstRealSnapshotDate,
            accountId: nil)
        guard !holdings.isEmpty else { return [] }

        let chartStartDay = HistoricalPriceCalendar.utcStartOfDay(for: chartStartDate)
        let windowPrices = prices.filter {
            $0.day >= chartStartDay && $0.day < source.firstRealSnapshotDate
        }
        return HistoricalPortfolioEstimator.estimatedValues(
            holdings: holdings,
            prices: windowPrices,
            startDate: chartStartDate,
            firstRealSnapshotDate: source.firstRealSnapshotDate,
            accountId: nil)
    }
}
