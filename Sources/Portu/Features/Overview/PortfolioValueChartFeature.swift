import Foundation
import PortuCore

/// Source data for the estimated pre-snapshot segment of the portfolio value chart, as values:
/// built by `PortfolioValueChartProjector.estimateSource`, so no model leaves that actor.
struct PortfolioValueChartEstimateSource: Equatable, Sendable {
    /// Timestamp of the globally-earliest non-ignored AssetSnapshot row: the holdings date.
    let firstRealSnapshotDate: Date
    /// Deduped value-type projections of the first-day AssetSnapshot rows —
    /// earliest per (accountId, assetId) key, matching `earliestEstimateHoldings` dedup.
    let firstDayEntries: [HistoricalEstimateSnapshotEntry]
    /// Timestamp of the earliest PortfolioSnapshot, the first point the chart draws.
    var firstRecordedDate: Date?

    var estimateEndDate: Date {
        HistoricalPortfolioEstimator.estimateEndDate(
            holdingsDate: firstRealSnapshotDate,
            firstRecordedDate: firstRecordedDate)
    }
}

enum PortfolioValueChartFeature {
    /// Pure estimate computation — no models in the signature; safe to call on the main actor
    /// from a `.task` closure without any blocking.
    ///
    /// The price filter (`>= chartStartDay`, `< firstRealSnapshotDate`) is applied here,
    /// preserving exact parity with the former `estimatedPoints` computed property. It keeps the
    /// holdings day's close as the reference price; the points still end at `estimateEndDate`.
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
            endDate: source.estimateEndDate,
            accountId: nil)
    }
}

/// One snapshot in the display currency.
struct PortfolioValueChartPoint: Equatable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let value: Decimal
    let isPartial: Bool
}

/// The value chart as drawn: its source converted into one display currency (#124, spec C3).
struct PortfolioValueChartData: Equatable, Sendable {
    /// The display currency the values were converted into.
    var currencyCode: String
    var snapshots: [PortfolioValueChartPoint]
    var estimated: [HistoricalPortfolioValuePoint]

    /// Converts as the chart's body did: the live rate for `today`'s UTC day, the stored row for an
    /// earlier day, and the live rate for a day with no row.
    static func converting(
        _ source: PortfolioValueChartSource,
        currency: FiatCurrency,
        usdToDisplayRate: Decimal,
        today: Date) -> PortfolioValueChartData {
        let context = CurrencyConversionContext(
            displayCurrency: currency,
            currentUSDToDisplayRate: usdToDisplayRate,
            historicalRates: source.rates)
        return PortfolioValueChartData(
            currencyCode: currency.displayCode,
            snapshots: source.snapshots.map { snapshot in
                PortfolioValueChartPoint(
                    id: snapshot.id,
                    timestamp: snapshot.timestamp,
                    value: context.convertUSDValue(snapshot.totalValueUSD, on: snapshot.timestamp, today: today),
                    isPartial: snapshot.isPartial)
            },
            estimated: source.estimatedUSD.map { context.convertUSDPoint($0, today: today) })
    }

    /// `converting` on the concurrent executor whatever the caller's isolation, so the reducer's
    /// effect converts off the main thread (spec C3).
    @concurrent
    static func convertingOffMain(
        _ source: PortfolioValueChartSource,
        currency: FiatCurrency,
        usdToDisplayRate: Decimal,
        today: Date) async -> PortfolioValueChartData {
        converting(source, currency: currency, usdToDisplayRate: usdToDisplayRate, today: today)
    }
}
