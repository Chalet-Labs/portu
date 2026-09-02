import Foundation
import PortuCore

/// Parses CoinGecko /simple/price JSON response via JSONSerialization.
/// Keys are coin IDs, values contain price in the requested fiat currency.
nonisolated struct CoinGeckoSimplePriceResponse {
    let prices: [String: Decimal]

    init(from data: Data, currency: FiatCurrency = .default) throws(PriceServiceError) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: NSNumber]] else {
            throw .decodingFailed
        }
        var result: [String: Decimal] = [:]
        for (coinId, currencies) in json {
            if let value = currencies[currency.coinGeckoParameter] {
                result[coinId] = value.decimalValue
            }
        }
        self.prices = result
    }

    /// Parse response that includes 24h change data.
    /// Format: `{ "bitcoin": { "eur": 67500.0, "eur_24h_change": -1.5 }, ... }`
    /// The change percentage is divided by 100 to convert from percentage to decimal.
    static func parsePriceUpdate(
        from data: Data,
        currency: FiatCurrency = .default) throws(PriceServiceError) -> PriceUpdate {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw .decodingFailed
        }
        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]
        let priceKey = currency.coinGeckoParameter
        let changeKey = "\(priceKey)_24h_change"
        for (coinId, values) in json {
            if let value = values[priceKey] as? NSNumber {
                prices[coinId] = value.decimalValue
            }
            if let change = values[changeKey] as? NSNumber {
                changes[coinId] = change.decimalValue / 100
            }
        }
        return PriceUpdate(currency: currency, prices: prices, changes24h: changes)
    }
}

nonisolated struct CoinGeckoMarketChartResponse {
    let prices: [HistoricalPriceDTO]

    init(
        coinGeckoId: String,
        currency: FiatCurrency = .default,
        data: Data) throws(PriceServiceError) {
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
                currency: currency,
                price: priceNumber.decimalValue)
            if let existing = latestByDay[dto.day], existing.timestamp >= dto.timestamp {
                continue
            }
            latestByDay[dto.day] = dto
        }

        self.prices = latestByDay.values.sorted {
            if $0.day != $1.day {
                return $0.day < $1.day
            }
            return $0.timestamp < $1.timestamp
        }
    }
}

nonisolated struct CoinGeckoTokenPriceResponse {
    let pricesByAddress: [String: Decimal]
    let changes24hByAddress: [String: Decimal]

    init(
        data: Data,
        currency: FiatCurrency = .default,
        chain: Chain) throws(PriceServiceError) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw .decodingFailed
        }

        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]
        let priceKey = currency.coinGeckoParameter
        let changeKey = "\(priceKey)_24h_change"
        for (address, values) in json {
            guard
                let normalizedAddress = OnchainTokenIdentity(
                    chain: Optional(chain),
                    contractAddress: Optional(address))?
                    .contractAddress
            else {
                continue
            }
            if let value = values[priceKey] as? NSNumber {
                prices[normalizedAddress] = value.decimalValue
            }
            if let change = values[changeKey] as? NSNumber {
                changes[normalizedAddress] = change.decimalValue / 100
            }
        }

        self.pricesByAddress = prices
        self.changes24hByAddress = changes
    }
}

nonisolated struct CoinGeckoExchangeRatesResponse {
    let rates: [FiatCurrency: Decimal]

    init(data: Data) throws(PriceServiceError) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = json["rates"] as? [String: [String: Any]]
        else {
            throw .decodingFailed
        }

        var rates: [FiatCurrency: Decimal] = [:]
        for (key, values) in rows {
            let currency = FiatCurrency(storageCode: key)
            guard
                currency.storageCode == key.lowercased(),
                let value = values["value"] as? NSNumber,
                value.decimalValue > 0
            else {
                continue
            }
            rates[currency] = value.decimalValue
        }
        self.rates = rates
    }
}

nonisolated struct CoinGeckoOnchainTokenMapResponse {
    let coinGeckoIDsByAddress: [String: String]

    init(data: Data, chain: Chain) throws(PriceServiceError) {
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
            let normalizedAddress = OnchainTokenIdentity(
                chain: Optional(chain),
                contractAddress: Optional(address))?
                .contractAddress
            let normalizedCoinGeckoID = coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let normalizedAddress, !normalizedCoinGeckoID.isEmpty else {
                continue
            }
            result[normalizedAddress] = normalizedCoinGeckoID
        }

        self.coinGeckoIDsByAddress = result
    }
}
