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

nonisolated struct CoinGeckoMarketChartResponse {
    let prices: [HistoricalPriceDTO]

    init(coinGeckoId: String, data: Data) throws(PriceServiceError) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = json["prices"] as? [[Any]]
        else {
            throw .decodingFailed
        }

        var latestByDay: [Date: HistoricalPriceDTO] = [:]
        for row in rows {
            guard
                row.count >= 2,
                let timestampNumber = row[0] as? NSNumber,
                let priceNumber = row[1] as? NSNumber
            else {
                throw .decodingFailed
            }
            let timestamp = Date(timeIntervalSince1970: timestampNumber.doubleValue / 1000)
            let dto = HistoricalPriceDTO(
                coinGeckoId: coinGeckoId,
                timestamp: timestamp,
                usdPrice: priceNumber.decimalValue)
            if let existing = latestByDay[dto.day], existing.timestamp >= dto.timestamp {
                continue
            }
            latestByDay[dto.day] = dto
        }

        self.prices = latestByDay.values.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.timestamp < $1.timestamp
        }
    }
}

nonisolated struct CoinGeckoTokenPriceResponse {
    let pricesByAddress: [String: Decimal]
    let changes24hByAddress: [String: Decimal]

    init(data: Data) throws(PriceServiceError) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw .decodingFailed
        }

        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]
        for (address, values) in json {
            let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedAddress.isEmpty else { continue }
            if let usd = values["usd"] as? NSNumber {
                prices[normalizedAddress] = usd.decimalValue
            }
            if let change = values["usd_24h_change"] as? NSNumber {
                changes[normalizedAddress] = change.decimalValue / 100
            }
        }

        self.pricesByAddress = prices
        self.changes24hByAddress = changes
    }
}

nonisolated struct CoinGeckoOnchainTokenMapResponse {
    let coinGeckoIDsByAddress: [String: String]

    init(data: Data) throws(PriceServiceError) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = json["data"] as? [[String: Any]]
        else {
            throw .decodingFailed
        }

        var result: [String: String] = [:]
        for row in rows {
            guard let attributes = row["attributes"] as? [String: Any] else {
                continue
            }
            guard
                let address = attributes["address"] as? String,
                let coinGeckoID = attributes["coingecko_coin_id"] as? String
            else {
                continue
            }
            let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedCoinGeckoID = coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedAddress.isEmpty, !normalizedCoinGeckoID.isEmpty else {
                continue
            }
            result[normalizedAddress] = normalizedCoinGeckoID
        }

        self.coinGeckoIDsByAddress = result
    }
}
