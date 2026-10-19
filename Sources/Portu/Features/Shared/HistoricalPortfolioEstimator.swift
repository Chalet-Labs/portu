import Foundation
import PortuCore

// swiftformat:disable redundantSendable

enum HistoricalPortfolioPointKind: Equatable, Sendable {
    case estimated
    case real
}

struct HistoricalPortfolioValuePoint: Equatable, Identifiable, Sendable {
    var id: String {
        "\(kind)-\(date.timeIntervalSince1970)"
    }

    let date: Date
    let value: Decimal
    let kind: HistoricalPortfolioPointKind
}

struct HistoricalEstimateHolding: Equatable, Sendable {
    let accountId: UUID
    let assetId: UUID
    let coinGeckoId: String
    let amount: Decimal
    let fallbackUSDValue: Decimal?

    init(
        accountId: UUID,
        assetId: UUID,
        coinGeckoId: String,
        amount: Decimal,
        fallbackUSDValue: Decimal? = nil) {
        self.accountId = accountId
        self.assetId = assetId
        self.coinGeckoId = coinGeckoId
        self.amount = amount
        self.fallbackUSDValue = fallbackUSDValue
    }
}

struct HistoricalPriceEntry: Equatable, Sendable {
    let coinGeckoId: String
    let day: Date
    let usdPrice: Decimal
}

enum HistoricalPortfolioEstimator {
    /// Where an estimate ends: the earlier of the holdings date and the first point the chart
    /// draws from the recorded series in that scope, so it never runs over that series (U7).
    static func estimateEndDate(holdingsDate: Date, firstRecordedDate: Date?) -> Date {
        firstRecordedDate.map { min($0, holdingsDate) } ?? holdingsDate
    }

    /// Estimated days in `[utcStartOfDay(startDate), utcStartOfDay(endDate))`. The reference
    /// prices always come from `firstRealSnapshotDate`, the holdings date; `endDate` can only end
    /// the points earlier (U7) and defaults to the holdings date.
    static func estimatedValues(
        holdings: [HistoricalEstimateHolding],
        prices: [HistoricalPriceEntry],
        startDate: Date,
        firstRealSnapshotDate: Date,
        endDate: Date? = nil,
        accountId: UUID?) -> [HistoricalPortfolioValuePoint] {
        let scopedHoldings = holdings.compactMap { holding -> HistoricalEstimateHolding? in
            guard
                accountId == nil || holding.accountId == accountId,
                let coinGeckoId = TokenIdentityMappingFeature.normalizedHistoricalPriceID(holding.coinGeckoId) else { return nil }
            return HistoricalEstimateHolding(
                accountId: holding.accountId,
                assetId: holding.assetId,
                coinGeckoId: coinGeckoId,
                amount: holding.amount,
                fallbackUSDValue: holding.fallbackUSDValue)
        }
        guard !scopedHoldings.isEmpty else { return [] }

        let startDay = HistoricalPriceCalendar.utcStartOfDay(for: startDate)
        let firstRealDay = HistoricalPriceCalendar.utcStartOfDay(for: firstRealSnapshotDate)
        let endDay = min(firstRealDay, HistoricalPriceCalendar.utcStartOfDay(for: endDate ?? firstRealSnapshotDate))
        var pricesByDay: [Date: [String: Decimal]] = [:]

        let normalizedPrices = prices.compactMap { price -> HistoricalPriceEntry? in
            guard let coinGeckoId = TokenIdentityMappingFeature.normalizedHistoricalPriceID(price.coinGeckoId) else { return nil }
            return HistoricalPriceEntry(coinGeckoId: coinGeckoId, day: price.day, usdPrice: price.usdPrice)
        }
        let referencePrices = referencePricesByID(prices: normalizedPrices, firstRealDay: firstRealDay)
        // HistoricalPriceEntry has no fetchedAt metadata. Sorting by day, id, then price
        // makes duplicate day/id rows deterministic; the highest price wins for exact duplicates.
        for price in normalizedPrices.sorted(by: priceSort) {
            let day = HistoricalPriceCalendar.utcStartOfDay(for: price.day)
            guard day >= startDay, day < endDay else {
                continue
            }
            pricesByDay[day, default: [:]][price.coinGeckoId] = price.usdPrice
        }

        return pricesByDay.keys.sorted().compactMap { day in
            let dayPrices = pricesByDay[day, default: [:]]
            var usedHistoricalPrice = false
            var canEstimateDay = true
            var value = Decimal.zero
            for holding in scopedHoldings {
                if
                    let fallbackUSDValue = holding.fallbackUSDValue,
                    let price = dayPrices[holding.coinGeckoId],
                    let referencePrice = referencePrices[holding.coinGeckoId],
                    referencePrice > 0 {
                    usedHistoricalPrice = true
                    value += fallbackUSDValue * price / referencePrice
                    continue
                }
                if let price = dayPrices[holding.coinGeckoId] {
                    usedHistoricalPrice = true
                    value += holding.amount * price
                    continue
                }
                guard let fallbackUSDValue = holding.fallbackUSDValue else {
                    canEstimateDay = false
                    break
                }
                value += fallbackUSDValue
            }
            guard canEstimateDay, usedHistoricalPrice else { return nil }
            return HistoricalPortfolioValuePoint(date: day, value: value, kind: .estimated)
        }
    }

    static func realValues(_ values: [(Date, Decimal)]) -> [HistoricalPortfolioValuePoint] {
        var latestByDay: [Date: (date: Date, value: Decimal)] = [:]
        for (date, value) in values {
            let day = HistoricalPriceCalendar.utcStartOfDay(for: date)
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
        let lhsDay = HistoricalPriceCalendar.utcStartOfDay(for: lhs.day)
        let rhsDay = HistoricalPriceCalendar.utcStartOfDay(for: rhs.day)
        if lhsDay != rhsDay {
            return lhsDay < rhsDay
        }
        if lhs.coinGeckoId != rhs.coinGeckoId {
            return lhs.coinGeckoId < rhs.coinGeckoId
        }
        return lhs.usdPrice < rhs.usdPrice
    }

    private static func referencePricesByID(
        prices: [HistoricalPriceEntry],
        firstRealDay: Date) -> [String: Decimal] {
        var latestByID: [String: (day: Date, price: Decimal)] = [:]
        for price in prices {
            let day = HistoricalPriceCalendar.utcStartOfDay(for: price.day)
            guard day <= firstRealDay, price.usdPrice > 0 else { continue }
            if let existing = latestByID[price.coinGeckoId] {
                guard day > existing.day || (day == existing.day && price.usdPrice > existing.price) else {
                    continue
                }
            }
            latestByID[price.coinGeckoId] = (day, price.usdPrice)
        }
        return latestByID.mapValues(\.price)
    }
}
