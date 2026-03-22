import Foundation

/// Parses CoinGecko /simple/price JSON response via JSONSerialization.
/// Keys are coin IDs, values contain price in USD and 24h change.
nonisolated
struct CoinGeckoSimplePriceResponse: Sendable {
    let prices: [String: Decimal]
    let changes24h: [String: Decimal]

    init(from data: Data) throws(PriceServiceError) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: NSNumber]] else {
            throw .decodingFailed
        }
        var prices: [String: Decimal] = [:]
        var changes24h: [String: Decimal] = [:]
        for (coinId, currencies) in json {
            if let usd = currencies["usd"] {
                prices[coinId] = usd.decimalValue
            }
            if let change = currencies["usd_24h_change"] {
                changes24h[coinId] = change.decimalValue
            }
        }
        self.prices = prices
        self.changes24h = changes24h
    }
}

/// Parses CoinGecko /coins/{id}/market_chart JSON response.
nonisolated
struct CoinGeckoMarketChartResponse: Sendable {
    let prices: [HistoricalPricePoint]

    init(from data: Data) throws(PriceServiceError) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["prices"] as? [[NSNumber]]
        else {
            throw .decodingFailed
        }

        let points = entries.compactMap { entry -> HistoricalPricePoint? in
            guard entry.count == 2 else { return nil }
            return HistoricalPricePoint(
                date: Date(timeIntervalSince1970: entry[0].doubleValue / 1000),
                price: entry[1].decimalValue
            )
        }

        guard points.count == entries.count else {
            throw .decodingFailed
        }

        self.prices = points.sorted { $0.date < $1.date }
    }
}
