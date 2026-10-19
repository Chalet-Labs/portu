import PortuCore
import SwiftData
import SwiftUI

extension EnvironmentValues {
    /// The historical half of the USD valuation inputs. It never carries the live book, so a live
    /// tick does not invalidate its readers.
    @Entry var historicalMarketPrices: HistoricalMarketPrices = .empty
}

/// Publishes the stored historical prices to the content: the USD closes and fractions valuation
/// reads.
struct HistoricalPricesProvider<Content: View>: View {
    @Query private var historicalPrices: [HistoricalPricePoint]
    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    private let now: Date
    private let content: Content

    init(now: Date = .now, @ViewBuilder content: () -> Content) {
        let startDate = MarketPrices.closeWindowStart(now: now)
        _historicalPrices = Query(
            filter: #Predicate<HistoricalPricePoint> { $0.day >= startDate },
            sort: [
                SortDescriptor(\HistoricalPricePoint.day),
                SortDescriptor(\HistoricalPricePoint.coinGeckoId)
            ])
        self.now = now
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.historicalMarketPrices, HistoricalMarketPricesFeature.prices(
                from: historicalPrices,
                isBackfillEnabled: historicalBackfillEnabled,
                now: now))
    }
}

enum HistoricalMarketPricesFeature {
    /// The USD closes and consecutive-day fractions of the stored rows. No currency or rate goes in:
    /// non-USD rows are dropped, never converted. With backfill disabled no row is read.
    static func prices(
        from rows: [HistoricalPricePoint],
        isBackfillEnabled: Bool,
        now: Date) -> HistoricalMarketPrices {
        guard isBackfillEnabled else { return .empty }
        return HistoricalMarketPrices(
            closeRows: rows.map(HistoricalCloseRow.init),
            isBackfillEnabled: true,
            now: now)
    }
}
