import Foundation

public enum ZerionChartPeriod: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case week
    case month
    case threeMonths = "3months"
    case year

    public static func yearToDate(at date: Date) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let elapsedDays = calendar.ordinality(of: .day, in: .year, for: date) ?? 365
        if elapsedDays <= 31 {
            return .month
        }
        if elapsedDays <= 90 {
            return .threeMonths
        }
        return .year
    }
}

struct ZerionWalletChartResource: Decodable {
    let attributes: Attributes

    struct Attributes: Decodable {
        let beginAt: String?
        let endAt: String?
        let points: [Point]

        enum CodingKeys: String, CodingKey {
            case beginAt = "begin_at"
            case endAt = "end_at"
            case points
        }
    }

    struct Point: Decodable {
        let timestamp: Double?
        let value: Decimal?

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let timestampDecoder = try? container.superDecoder()
            let valueDecoder = try? container.superDecoder()
            self.timestamp = timestampDecoder.flatMap {
                try? $0.singleValueContainer().decode(Double.self)
            }
            self.value = valueDecoder.flatMap {
                try? $0.singleValueContainer().decode(Decimal.self)
            }
        }
    }
}
