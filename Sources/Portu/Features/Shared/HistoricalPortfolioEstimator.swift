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
        let scopedHoldings = holdings.compactMap { holding -> HistoricalEstimateHolding? in
            guard accountId == nil || holding.accountId == accountId else { return nil }
            let coinGeckoId = normalizedID(holding.coinGeckoId)
            guard !coinGeckoId.isEmpty else { return nil }
            return HistoricalEstimateHolding(
                accountId: holding.accountId,
                assetId: holding.assetId,
                coinGeckoId: coinGeckoId,
                amount: holding.amount)
        }
        guard !scopedHoldings.isEmpty else { return [] }

        let startDay = utcStartOfDay(for: startDate)
        let firstRealDay = utcStartOfDay(for: firstRealSnapshotDate)
        let requiredIDs = Set(scopedHoldings.map(\.coinGeckoId))
        var pricesByDay: [Date: [String: Decimal]] = [:]

        let normalizedPrices = prices.compactMap { price -> HistoricalPriceEntry? in
            let coinGeckoId = normalizedID(price.coinGeckoId)
            guard !coinGeckoId.isEmpty else { return nil }
            return HistoricalPriceEntry(coinGeckoId: coinGeckoId, day: price.day, usdPrice: price.usdPrice)
        }
        // HistoricalPriceEntry has no fetchedAt metadata. Sorting by day, id, then price
        // makes duplicate day/id rows deterministic; the highest price wins for exact duplicates.
        for price in normalizedPrices.sorted(by: priceSort) {
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
        var latestByDay: [Date: (date: Date, value: Decimal)] = [:]
        for (date, value) in values {
            let day = utcStartOfDay(for: date)
            if let existing = latestByDay[day], existing.date > date || (existing.date == date && existing.value >= value) {
                continue
            }
            latestByDay[day] = (date, value)
        }

        return latestByDay.keys.sorted().map { day in
            HistoricalPortfolioValuePoint(date: day, value: latestByDay[day]?.value ?? 0, kind: .real)
        }
    }

    private static func priceSort(_ lhs: HistoricalPriceEntry, _ rhs: HistoricalPriceEntry) -> Bool {
        let lhsDay = utcStartOfDay(for: lhs.day)
        let rhsDay = utcStartOfDay(for: rhs.day)
        if lhsDay != rhsDay { return lhsDay < rhsDay }
        if lhs.coinGeckoId != rhs.coinGeckoId { return lhs.coinGeckoId < rhs.coinGeckoId }
        return lhs.usdPrice < rhs.usdPrice
    }

    private static func normalizedID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func utcStartOfDay(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.startOfDay(for: date)
    }
}
