import Foundation
import PortuCore

/// Parses CoinGecko /simple/price JSON response via JSONSerialization.
/// Keys are coin IDs, values contain price in USD.
nonisolated struct CoinGeckoSimplePriceResponse {
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

    /// Parse response that includes 24h change data.
    /// Format: `{ "bitcoin": { "usd": 67500.0, "usd_24h_change": -1.5 }, ... }`
    /// The change percentage is divided by 100 to convert from percentage to decimal.
    static func parsePriceUpdate(from data: Data) throws(PriceServiceError) -> PriceUpdate {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw .decodingFailed
        }
        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]
        for (coinId, values) in json {
            if let usd = values["usd"] as? NSNumber {
                prices[coinId] = usd.decimalValue
            }
            if let change = values["usd_24h_change"] as? NSNumber {
                changes[coinId] = change.decimalValue / 100
            }
        }
        return PriceUpdate(prices: prices, changes24h: changes)
    }
}
