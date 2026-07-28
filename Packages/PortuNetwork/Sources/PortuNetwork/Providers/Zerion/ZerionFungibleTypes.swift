import Foundation

struct ZerionFungibleResource: Decodable {
    let attributes: Attributes

    struct Attributes: Decodable {
        let marketData: MarketData?
        let implementations: [ZerionPositionResource.Implementation]

        enum CodingKeys: String, CodingKey {
            case marketData = "market_data"
            case implementations
        }
    }

    struct MarketData: Decodable {
        let price: Decimal?
        let changes: Changes?
    }

    struct Changes: Decodable {
        let percent1D: Decimal?

        enum CodingKeys: String, CodingKey {
            case percent1D = "percent_1d"
        }
    }
}

struct ZerionChartResource: Decodable {
    let attributes: Attributes

    struct Attributes: Decodable {
        let points: [Point]
    }

    struct Point: Decodable {
        let timestamp: Double
        let price: Decimal

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.timestamp = try container.decode(Double.self)
            self.price = try container.decode(Decimal.self)
        }
    }
}
