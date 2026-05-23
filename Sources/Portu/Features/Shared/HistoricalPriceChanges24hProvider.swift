import PortuCore
import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var historicalPriceChanges24h: [String: Decimal] = [:]
    @Entry var historicalPricesUSD: [String: Decimal] = [:]
}

struct HistoricalPriceChanges24hProvider<Content: View>: View {
    @Query private var historicalPrices: [HistoricalPricePoint]
    @AppStorage(HistoricalPriceBackfillSettings.isEnabledKey)
    private var historicalBackfillEnabled = HistoricalPriceBackfillSettings.defaultIsEnabled

    private let content: Content

    init(now: Date = .now, @ViewBuilder content: () -> Content) {
        let startDate = OverviewHistoricalPriceChangeFeature.queryStartDate(now: now)
        _historicalPrices = Query(
            filter: #Predicate<HistoricalPricePoint> { $0.day >= startDate },
            sort: [
                SortDescriptor(\HistoricalPricePoint.day),
                SortDescriptor(\HistoricalPricePoint.coinGeckoId)
            ])
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.historicalPriceChanges24h, historicalBackfillEnabled ? historicalChanges24h : [:])
            .environment(\.historicalPricesUSD, historicalBackfillEnabled ? historicalPricesUSD : [:])
    }

    private var historicalEntries: [HistoricalPriceEntry] {
        historicalPrices.map {
            HistoricalPriceEntry(coinGeckoId: $0.coinGeckoId, day: $0.day, usdPrice: $0.usdPrice)
        }
    }

    private var historicalChanges24h: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.changes24h(from: historicalEntries)
    }

    private var historicalPricesUSD: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.latestPrices(from: historicalEntries)
    }
}
