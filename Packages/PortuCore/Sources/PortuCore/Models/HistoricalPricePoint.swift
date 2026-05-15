import Foundation
import SwiftData

public enum HistoricalPriceSource: String, Codable, Sendable, Equatable {
    case coingecko
    case zapper
}

@Model
public final class HistoricalPricePoint {
    #Index<HistoricalPricePoint>([\.day], [\.coinGeckoId, \.day])

    @Attribute(.unique) public var id: UUID
    public var coinGeckoId: String
    public var day: Date
    public var usdPrice: Decimal
    public var source: HistoricalPriceSource
    public var fetchedAt: Date

    public init(
        id: UUID = UUID(),
        coinGeckoId: String,
        day: Date,
        usdPrice: Decimal,
        source: HistoricalPriceSource = .coingecko,
        fetchedAt: Date = .now) {
        self.id = id
        self.coinGeckoId = coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.usdPrice = usdPrice
        self.source = source
        self.fetchedAt = fetchedAt
    }

    public convenience init(dto: HistoricalPriceDTO, fetchedAt: Date = .now) {
        self.init(
            coinGeckoId: dto.coinGeckoId,
            day: dto.day,
            usdPrice: dto.usdPrice,
            source: dto.source,
            fetchedAt: fetchedAt)
    }
}
