import Foundation
import PortuCore

extension PerformanceDataShaping {
    /// Merges historical price rows into display-currency entries, preferring rows already stored in the
    /// display currency and converting USD rows as a fallback, then sorts by coinGeckoId then day.
    /// The price-change panel is the only reader.
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
