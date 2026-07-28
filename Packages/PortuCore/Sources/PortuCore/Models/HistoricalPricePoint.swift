import Foundation
import SwiftData

public enum HistoricalPriceSource: String, Codable, Sendable, Equatable {
    case coingecko
    case zapper
    case zerion
}

@Model
public final class HistoricalPricePoint {
    #Index<HistoricalPricePoint>([\.day], [\.coinGeckoId, \.day])

    @Attribute(.unique) public var id: UUID
    public var coinGeckoId: String
    public var day: Date
    public var currency: FiatCurrency? = FiatCurrency.usd
    @Attribute(originalName: "usdPrice") public var price: Decimal
    public var source: HistoricalPriceSource
    public var fetchedAt: Date

    public var fiatCurrency: FiatCurrency {
        currency ?? .usd
    }

    public var usdPrice: Decimal {
        get { price }
        set { price = newValue }
    }

    public convenience init(
        id: UUID = UUID(),
        coinGeckoId: String,
        day: Date,
        usdPrice: Decimal,
        source: HistoricalPriceSource = .coingecko,
        fetchedAt: Date = .now) {
        self.init(
            id: id,
            coinGeckoId: coinGeckoId,
            day: day,
            currency: .usd,
            price: usdPrice,
            source: source,
            fetchedAt: fetchedAt)
    }

    public init(
        id: UUID = UUID(),
        coinGeckoId: String,
        day: Date,
        currency: FiatCurrency = .usd,
        price: Decimal,
        source: HistoricalPriceSource = .coingecko,
        fetchedAt: Date = .now) {
        self.id = id
        self.coinGeckoId = OnchainTokenIdentity.normalizedHistoricalPriceID(coinGeckoId)
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.currency = currency
        self.price = price
        self.source = source
        self.fetchedAt = fetchedAt
    }

    public convenience init(dto: HistoricalPriceDTO, fetchedAt: Date = .now) {
        self.init(
            coinGeckoId: dto.coinGeckoId,
            day: dto.day,
            currency: dto.currency,
            price: dto.price,
            source: dto.source,
            fetchedAt: fetchedAt)
    }
}
