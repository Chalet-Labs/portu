import PortuCore
import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var historicalPriceChanges24h: [String: Decimal] = [:]
    @Entry var historicalDisplayPrices: [String: Decimal] = [:]
}

struct HistoricalPriceChanges24hProvider<Content: View>: View {
    @Environment(AppState.self) private var appState

    @Query private var historicalPrices: [HistoricalPricePoint]
    @Query
    private var currencyRates: [CurrencyConversionRatePoint]
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
        _currencyRates = Query(
            filter: #Predicate<CurrencyConversionRatePoint> { $0.day >= startDate },
            sort: \.day)
        self.content = content()
    }

    var body: some View {
        let (changes24h, displayPrices): ([String: Decimal], [String: Decimal])
        if historicalBackfillEnabled {
            let entries = historicalEntries
            changes24h = OverviewHistoricalPriceChangeFeature.changes24h(from: entries)
            displayPrices = OverviewHistoricalPriceChangeFeature.latestPrices(from: entries)
        } else {
            changes24h = [:]
            displayPrices = [:]
        }
        return content
            .environment(\.historicalPriceChanges24h, changes24h)
            .environment(\.historicalDisplayPrices, displayPrices)
    }

    private var historicalEntries: [HistoricalPriceEntry] {
        let context = CurrencyConversionContext(
            displayCurrency: appState.selectedCurrency,
            currentUSDToDisplayRate: appState.currentUSDToDisplayRate,
            historicalRatePoints: currencyRates)
        return OverviewHistoricalPriceChangeFeature.mergedHistoricalPriceEntries(
            from: historicalPrices,
            displayCurrency: appState.selectedCurrency,
            context: context)
    }
}

extension OverviewHistoricalPriceChangeFeature {
    /// Merges historical price rows into display-currency entries, preferring rows already stored in the
    /// display currency and converting USD rows as a fallback, then sorts by coinGeckoId then day.
    static func mergedHistoricalPriceEntries(
        from rows: [HistoricalPricePoint],
        displayCurrency: FiatCurrency,
        context: CurrencyConversionContext) -> [HistoricalPriceEntry] {
        struct PriceKey: Hashable {
            let coinGeckoId: String
            let day: Date
        }

        var selectedRows: [PriceKey: HistoricalPriceEntry] = [:]
        var usdFallbackRows: [PriceKey: HistoricalPriceEntry] = [:]

        let orderedRows = rows.sorted { lhs, rhs in
            if lhs.fetchedAt == rhs.fetchedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.fetchedAt < rhs.fetchedAt
        }
        for row in orderedRows {
            guard let historicalPriceID = TokenIdentityMappingFeature.normalizedHistoricalPriceID(row.coinGeckoId) else {
                continue
            }
            let key = PriceKey(
                coinGeckoId: historicalPriceID,
                day: HistoricalPriceCalendar.utcStartOfDay(for: row.day))
            if row.fiatCurrency == displayCurrency {
                selectedRows[key] = HistoricalPriceEntry(
                    coinGeckoId: historicalPriceID,
                    day: key.day,
                    usdPrice: row.price)
            } else if row.fiatCurrency == .usd {
                usdFallbackRows[key] = HistoricalPriceEntry(
                    coinGeckoId: historicalPriceID,
                    day: key.day,
                    usdPrice: context.convertUSDValue(row.price, on: row.day))
            }
        }

        return (Array(selectedRows.values) + usdFallbackRows.compactMap { key, value in
            selectedRows[key] == nil ? value : nil
        })
        .sorted {
            if $0.coinGeckoId != $1.coinGeckoId {
                return $0.coinGeckoId < $1.coinGeckoId
            }
            return $0.day < $1.day
        }
    }
}
