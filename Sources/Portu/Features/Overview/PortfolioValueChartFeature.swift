// Sources/Portu/Features/Overview/PortfolioValueChartFeature.swift
import Foundation
import PortuCore
import SwiftData

/// Source data for the estimated pre-snapshot segment of the portfolio value chart.
/// Fetched from SwiftData at the model boundary so no live models escape into body.
struct PortfolioValueChartEstimateSource: Equatable {
    /// Timestamp of the globally-earliest AssetSnapshot row.
    let firstRealSnapshotDate: Date
    /// Value-type projections of every AssetSnapshot whose UTC day matches `firstRealSnapshotDate`.
    let firstDayEntries: [HistoricalEstimateSnapshotEntry]
}

enum PortfolioValueChartFeature {
    /// Fetches the minimum AssetSnapshot rows required to back-fill the chart's estimated segment.
    ///
    /// Only rows on the earliest UTC day matter; later rows cannot affect the estimate because
    /// `PerformanceFeature.earliestEstimateHoldings` deduplicates by (accountId, assetId) key
    /// using only the day that matches `firstRealSnapshotDate`.
    ///
    /// Returns `nil` when the store is empty, or when the earliest snapshot precedes
    /// `chartStartDate` (parity guard: the old full-table path produced an empty estimate in
    /// that case because the price-window filter `[chartStartDay, firstRealDay)` would be empty).
    static func estimateSource(
        modelContext: ModelContext,
        overrides: [TokenPricingOverrideSnapshot],
        chartStartDate: Date) -> PortfolioValueChartEstimateSource? {
        // 1. Globally-earliest AssetSnapshot — limit-1 fetch, no full table scan.
        var earliestDescriptor = FetchDescriptor<AssetSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        earliestDescriptor.fetchLimit = 1
        guard let earliest = (try? modelContext.fetch(earliestDescriptor))?.first else { return nil }

        // Parity guard: when earliest < chartStart, the price window [chartStartDay, firstRealDay)
        // is empty (firstRealDay ≤ chartStart ≤ chartStartDay), so the estimator returns [].
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

        // 3. Only the Asset rows referenced by the day rows — never the full Asset table.
        let assetIDs = Array(Set(dayRows.map(\.assetId)))
        var assetsById: [UUID: Asset] = [:]
        if !assetIDs.isEmpty {
            let assetDescriptor = FetchDescriptor<Asset>(
                predicate: #Predicate<Asset> { assetIDs.contains($0.id) })
            if let assets = try? modelContext.fetch(assetDescriptor) {
                assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            }
        }

        // 4. Project to value types with the same field mapping as the former view property.
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(overrides)
        let entries: [HistoricalEstimateSnapshotEntry] = dayRows.map { snapshot in
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
