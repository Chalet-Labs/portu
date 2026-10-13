import Foundation

/// One stored daily close, tagged with its currency. Projected from `HistoricalPricePoint` at the
/// SwiftData boundary; valuation only ever reads the USD rows.
public struct HistoricalCloseRow: Equatable, Sendable {
    public let priceID: String
    public let day: Date
    public let currency: FiatCurrency
    public let price: Decimal

    public init(priceID: String, day: Date, currency: FiatCurrency, price: Decimal) {
        self.priceID = priceID
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.currency = currency
        self.price = price
    }
}

/// The historical half of the USD price inputs (spec I1): the latest close per price ID with its UTC
/// day, and the consecutive-day 24h fractions. It has no live book, so views that read it are not
/// invalidated by live ticks; `MarketPrices(liveUSD:liveChanges24h:historical:)` joins the two.
public struct HistoricalMarketPrices: Equatable, Sendable {
    public static let empty = HistoricalMarketPrices()

    public let closesUSD: [String: HistoricalClose]
    public let changes24h: [String: Decimal]

    public init(closesUSD: [String: HistoricalClose] = [:], changes24h: [String: Decimal] = [:]) {
        self.closesUSD = closesUSD
        self.changes24h = changes24h
    }

    /// USD rows inside today's window only; empty when historical backfill is disabled.
    public init(closeRows: [HistoricalCloseRow], isBackfillEnabled: Bool, now: Date = .now) {
        guard isBackfillEnabled else {
            self.init()
            return
        }
        let windowStart = MarketPrices.closeWindowStart(now: now)
        let rows = closeRows.filter { $0.day >= windowStart }
        self.init(closesUSD: MarketPrices.latestCloses(from: rows), changes24h: MarketPrices.changes24h(from: rows))
    }
}

/// The USD price inputs of a valuation (spec I1): the live book, the latest close per price ID and
/// the merged 24h fractions. Keys are normalized price IDs. There is deliberately no merged book:
/// a close only competes with the sync value (V1.5), never with a live price.
public struct MarketPrices: Equatable, Sendable {
    public let liveUSD: [String: Decimal]
    public let closesUSD: [String: HistoricalClose]
    public let changes24h: [String: Decimal]

    public init(
        liveUSD: [String: Decimal] = [:],
        closesUSD: [String: HistoricalClose] = [:],
        changes24h: [String: Decimal] = [:]) {
        self.liveUSD = Self.normalizedKeys(liveUSD)
        self.closesUSD = Self.normalizedKeys(closesUSD)
        self.changes24h = Self.normalizedKeys(changes24h)
    }

    /// Builds the inputs from the live book, the live fractions and the stored close rows. Closes and
    /// historical fractions come from USD rows inside today's window, and are empty when historical
    /// backfill is disabled.
    public init(
        liveUSD: [String: Decimal],
        liveChanges24h: [String: Decimal],
        closeRows: [HistoricalCloseRow],
        isBackfillEnabled: Bool,
        now: Date = .now) {
        self.init(
            liveUSD: liveUSD,
            liveChanges24h: liveChanges24h,
            historical: HistoricalMarketPrices(closeRows: closeRows, isBackfillEnabled: isBackfillEnabled, now: now))
    }

    /// Joins the live book and live fractions with the historical half. Live fractions win.
    public init(
        liveUSD: [String: Decimal],
        liveChanges24h: [String: Decimal],
        historical: HistoricalMarketPrices) {
        self.init(
            liveUSD: liveUSD,
            closesUSD: historical.closesUSD,
            changes24h: Self.mergedChanges24h(live: liveChanges24h, historical: historical.changes24h))
    }

    /// The first day whose closes count as current: UTC today minus two days.
    public static func closeWindowStart(now: Date = .now) -> Date {
        HistoricalPriceCalendar.utcStartOfDay(for: now).addingTimeInterval(-2 * secondsPerDay)
    }

    /// The latest positive USD close per price ID. Two closes on the same day keep the higher price.
    public static func latestCloses(from rows: [HistoricalCloseRow]) -> [String: HistoricalClose] {
        var latest: [String: HistoricalClose] = [:]
        for row in rows {
            guard let id = usableID(of: row) else { continue }
            let close = HistoricalClose(day: row.day, price: row.price)
            if let existing = latest[id], !isPreferred(close, over: existing) {
                continue
            }
            latest[id] = close
        }
        return latest
    }

    /// The 24h fraction between the two latest USD closes of each price ID, only when they fall on
    /// consecutive UTC days.
    public static func changes24h(from rows: [HistoricalCloseRow]) -> [String: Decimal] {
        var byDay: [String: [Date: Decimal]] = [:]
        for row in rows {
            guard let id = usableID(of: row) else { continue }
            byDay[id, default: [:]][row.day] = max(byDay[id]?[row.day] ?? 0, row.price)
        }

        var changes: [String: Decimal] = [:]
        for (id, closes) in byDay {
            let days = closes.keys.sorted(by: >)
            guard
                days.count >= 2,
                days[0].timeIntervalSince(days[1]) == secondsPerDay,
                let latest = closes[days[0]],
                let previous = closes[days[1]]
            else { continue }
            changes[id] = (latest - previous) / previous
        }
        return changes
    }

    /// Live fractions win over historical ones for the same price ID.
    public static func mergedChanges24h(
        live: [String: Decimal],
        historical: [String: Decimal]) -> [String: Decimal] {
        normalizedKeys(historical).merging(normalizedKeys(live)) { _, live in live }
    }

    /// The unit price of a coin that is watched but not held: the live price, else the latest close,
    /// with the merged fraction.
    public func quote(priceID: String?) -> RowPricing {
        guard let id = TokenIdentityMappingFeature.normalizedHistoricalPriceID(priceID) else { return .none }
        if let live = liveUSD[id], live > 0 {
            return RowPricing(price: live, source: .live, fraction24h: changes24h[id])
        }
        if let close = closesUSD[id], close.price > 0 {
            return RowPricing(price: close.price, source: .close, fraction24h: changes24h[id])
        }
        return .none
    }

    private static let secondsPerDay: TimeInterval = 86400

    private static func usableID(of row: HistoricalCloseRow) -> String? {
        guard row.currency == .usd, row.price > 0 else { return nil }
        return TokenIdentityMappingFeature.normalizedHistoricalPriceID(row.priceID)
    }

    private static func isPreferred(_ candidate: HistoricalClose, over existing: HistoricalClose) -> Bool {
        candidate.day > existing.day || (candidate.day == existing.day && candidate.price > existing.price)
    }

    private static func normalizedKeys<Value>(_ book: [String: Value]) -> [String: Value] {
        var normalized: [String: Value] = [:]
        normalized.reserveCapacity(book.count)
        for (key, value) in book {
            guard let id = TokenIdentityMappingFeature.normalizedHistoricalPriceID(key) else { continue }
            normalized[id] = value
        }
        return normalized
    }
}
