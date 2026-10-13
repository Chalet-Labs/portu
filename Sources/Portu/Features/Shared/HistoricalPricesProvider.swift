import PortuCore
import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var historicalDisplayPrices: [String: Decimal] = [:]
    /// The historical half of the USD valuation inputs. It never carries the live book, so a live
    /// tick does not invalidate its readers.
    @Entry var historicalMarketPrices: HistoricalMarketPrices = .empty
}

/// Publishes the stored historical prices to the content: the USD closes and fractions valuation
/// reads, and the display-currency closes Assets, Exposure and Performance still read.
struct HistoricalPricesProvider<Content: View>: View {
    @Environment(AppState.self) private var appState

    @Query private var historicalPrices: [HistoricalPricePoint]
    @Query
    private var currencyRates: [CurrencyConversionRatePoint]
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
        _currencyRates = Query(
            filter: #Predicate<CurrencyConversionRatePoint> { $0.day >= startDate },
            sort: \.day)
        self.now = now
        self.content = content()
    }

    var body: some View {
        let displayPrices: [String: Decimal] = if historicalBackfillEnabled {
            OverviewHistoricalPriceChangeFeature.latestPrices(from: historicalEntries)
        } else {
            [:]
        }
        return content
            .environment(\.historicalDisplayPrices, displayPrices)
            .environment(\.historicalMarketPrices, HistoricalMarketPricesFeature.prices(
                from: historicalPrices,
                isBackfillEnabled: historicalBackfillEnabled,
                now: now))
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
