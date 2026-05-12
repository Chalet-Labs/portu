import Foundation

enum HistoricalPortfolioPointKind: Equatable {
    case estimated
    case real
}

struct HistoricalPortfolioValuePoint: Equatable, Identifiable {
    var id: String {
        "\(kind)-\(date.timeIntervalSince1970)"
    }

    let date: Date
    let value: Decimal
    let kind: HistoricalPortfolioPointKind
}

struct HistoricalEstimateHolding: Equatable {
    let accountId: UUID
    let assetId: UUID
    let coinGeckoId: String
    let amount: Decimal
}

struct HistoricalPriceEntry: Equatable {
    let coinGeckoId: String
    let day: Date
    let usdPrice: Decimal
}

enum HistoricalPortfolioEstimator {
    static func estimatedValues(
        holdings: [HistoricalEstimateHolding],
        prices: [HistoricalPriceEntry],
        startDate: Date,
        firstRealSnapshotDate: Date,
        accountId: UUID?) -> [HistoricalPortfolioValuePoint] {
        let scopedHoldings = holdings.filter { holding in
            accountId == nil || holding.accountId == accountId
        }
        guard !scopedHoldings.isEmpty else { return [] }

        let startDay = utcStartOfDay(for: startDate)
        let firstRealDay = utcStartOfDay(for: firstRealSnapshotDate)
        let requiredIDs = Set(scopedHoldings.map(\.coinGeckoId))
        var pricesByDay: [Date: [String: Decimal]] = [:]

        for price in prices {
            let day = utcStartOfDay(for: price.day)
            guard day >= startDay, day < firstRealDay else {
                continue
            }
            pricesByDay[day, default: [:]][price.coinGeckoId] = price.usdPrice
        }

        return pricesByDay.keys.sorted().compactMap { day in
            let dayPrices = pricesByDay[day, default: [:]]
            guard requiredIDs.allSatisfy({ dayPrices[$0] != nil }) else { return nil }
            let value = scopedHoldings.reduce(Decimal.zero) { partial, holding in
                partial + holding.amount * (dayPrices[holding.coinGeckoId] ?? 0)
            }
            return HistoricalPortfolioValuePoint(date: day, value: value, kind: .estimated)
        }
    }

    static func realValues(_ values: [(Date, Decimal)]) -> [HistoricalPortfolioValuePoint] {
        values
            .sorted { $0.0 < $1.0 }
            .map { HistoricalPortfolioValuePoint(date: utcStartOfDay(for: $0.0), value: $0.1, kind: .real) }
    }

    private static func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.startOfDay(for: date)
    }
}
