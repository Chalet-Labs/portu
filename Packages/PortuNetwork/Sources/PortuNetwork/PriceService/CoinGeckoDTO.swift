import Foundation

/// Parses CoinGecko /simple/price JSON response via JSONSerialization.
/// Keys are coin IDs, values contain price in USD.
nonisolated
struct CoinGeckoSimplePriceResponse: Sendable {
    let prices: [String: Decimal]

    init(from data: Data) throws(PriceServiceError) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: NSNumber]] else {
            throw .decodingFailed
        }
        var result: [String: Decimal] = [:]
        for (coinId, currencies) in json {
            if let usd = currencies["usd"] {
                result[coinId] = usd.decimalValue
            }
        }
        self.prices = result
    }
}
