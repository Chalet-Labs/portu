import Foundation

/// How a dashboard list builds its rows (F1) and which value it shows and sums (A7).
public enum DashboardBasis: Sendable {
    /// Positive-role tokens only; shows gross. The donut (and Exposure's spot, through `ratio(of:to:)`).
    case gross
    /// Borrow tokens only; shows debt. The Borrowing tab.
    case debt
    /// Every token; shows net. The Overview Idle and Key Changes tabs (which admit positive roles
    /// only, so their net is their gross), the watchlist and polling, Exposure, Assets, Platforms,
    /// Networks, Performance, Token Settings.
    case net
    /// Every token, keeping only rows whose net is positive; shows net. The Health weight list.
    case positiveNet

    func admits(_ role: TokenRole) -> Bool {
        switch self {
        case .gross: role.isPositive
        case .debt: role.isBorrow
        case .net, .positiveNet: true
        }
    }
}

/// F1 status of a row. The first match wins.
public enum RowStatus: Sendable {
    /// Every counted token is ignored.
    case ignored
    /// No counted token at all (rewards, zero amounts).
    case notCounted
    /// Every non-ignored counted token is unpriced.
    case unpriced
    /// The filter value is below the USD threshold.
    case dust
    case priced

    /// Ignored and not-counted rows never appear on a dashboard, not even in the hidden line.
    public var isDashboardRow: Bool {
        self != .ignored && self != .notCounted
    }
}

/// One displayed row: the tokens grouped under a caller key, valued and classified.
public struct DashboardRow<Key: Hashable & Sendable>: Equatable, Sendable {
    public let key: Key
    public let tokens: [ValuedToken]
    public let totals: ValuationTotals
    public let status: RowStatus
    public let alwaysShow: Bool
    public let isVisible: Bool
    /// The row's value on the list's basis.
    public let value: Decimal
    /// The larger of the row's gross and debt, in USD: what the dust rule compares.
    public let filterValue: Decimal

    /// V5 price, source and fraction.
    public var pricing: RowPricing {
        RowPricing(tokens: tokens)
    }

    public func displayValue(rate: Decimal) -> Decimal {
        value * rate
    }

    init(key: Key, tokens: [ValuedToken], basis: DashboardBasis, settings: TokenDashboardSettings) {
        let classification = RowClassification(tokens, settings: settings)
        self.key = key
        self.tokens = tokens
        self.totals = classification.totals
        self.status = classification.status
        self.alwaysShow = classification.alwaysShow
        self.isVisible = classification.isVisible
        self.value = classification.totals.value(on: basis)
        self.filterValue = classification.filterValue
    }
}

/// F1 and F2 over a constructed row. No rate: the threshold and the values are USD.
struct RowClassification {
    let totals: ValuationTotals
    let status: RowStatus
    let alwaysShow: Bool
    let isVisible: Bool
    let filterValue: Decimal

    init(_ tokens: [ValuedToken], settings: TokenDashboardSettings) {
        let totals = ValuationTotals(tokens)
        let filterValue = max(totals.gross, totals.debt)
        let counted = tokens.filter(\.isCounted)
        let considered = counted.filter { !$0.isIgnored }

        let status: RowStatus = if counted.isEmpty {
            .notCounted
        } else if considered.isEmpty {
            .ignored
        } else if considered.allSatisfy({ $0.source == .unpriced }) {
            .unpriced
        } else if filterValue < settings.dustThresholdUSD {
            .dust
        } else {
            .priced
        }
        // A non-counted token (a reward, a zero amount) never enters the row, so its asset can't show it.
        let alwaysShow = counted.contains(where: \.alwaysShow)

        self.totals = totals
        self.status = status
        self.alwaysShow = alwaysShow
        self.filterValue = filterValue
        self.isVisible = switch status {
        case .ignored, .notCounted: false
        case .unpriced: alwaysShow || !settings.hideUnpriced
        case .dust: alwaysShow || !settings.hideDust
        case .priced: true
        }
    }
}

/// The rows the display filter hides (F1–F3), summed on all three bases.
public struct HiddenBalances: Equatable, Sendable {
    public internal(set) var rowCount = 0
    public internal(set) var unpricedCount = 0
    public internal(set) var gross: Decimal = 0
    public internal(set) var debt: Decimal = 0

    public var net: Decimal {
        gross - debt
    }

    public var isEmpty: Bool {
        rowCount == 0
    }

    /// "in N small balances" when true, "in N hidden balances" otherwise.
    public var isAllDust: Bool {
        unpricedCount == 0
    }

    public func value(on basis: DashboardBasis) -> Decimal {
        switch basis {
        case .gross: gross
        case .debt: debt
        case .net, .positiveNet: net
        }
    }

    public func display(rate: Decimal) -> HiddenBalances {
        HiddenBalances(rowCount: rowCount, unpricedCount: unpricedCount, gross: gross * rate, debt: debt * rate)
    }

    mutating func add(_ row: DashboardRow<some Hashable & Sendable>) {
        rowCount += 1
        if row.status == .unpriced {
            unpricedCount += 1
        }
        gross += row.totals.gross
        debt += row.totals.debt
    }
}

/// A dashboard list: rows built on one basis, classified by the display filter, and the
/// hidden-balances summary. The filter never changes `total`.
public struct DashboardList<Key: Hashable & Sendable>: Equatable, Sendable {
    public let basis: DashboardBasis
    /// Every row in order of first appearance, including ignored and not-counted ones (Token
    /// Settings lists those too).
    public let rows: [DashboardRow<Key>]
    public let hidden: HiddenBalances
    /// The list's totals over every row.
    public let totals: ValuationTotals

    public init(
        _ tokens: some Sequence<ValuedToken>,
        basis: DashboardBasis,
        settings: TokenDashboardSettings,
        groupedBy key: (ValuedToken) -> Key) {
        var order: [Key] = []
        var groups: [Key: [ValuedToken]] = [:]
        for token in tokens where basis.admits(token.token.role) {
            let rowKey = key(token)
            if groups[rowKey] == nil {
                order.append(rowKey)
            }
            groups[rowKey, default: []].append(token)
        }

        var rows = order.map { DashboardRow(key: $0, tokens: groups[$0] ?? [], basis: basis, settings: settings) }
        if basis == .positiveNet {
            rows.removeAll { $0.totals.net <= 0 }
        }

        var hidden = HiddenBalances()
        for row in rows where row.status.isDashboardRow && !row.isVisible {
            hidden.add(row)
        }

        self.basis = basis
        self.rows = rows
        self.hidden = hidden
        self.totals = rows.reduce(.zero) { $0 + $1.totals }
    }

    public var dashboardRows: [DashboardRow<Key>] {
        rows.filter(\.status.isDashboardRow)
    }

    public var visibleRows: [DashboardRow<Key>] {
        rows.filter(\.isVisible)
    }

    /// The list total on its basis: visible rows + remainder + hidden line.
    public var total: Decimal {
        totals.value(on: basis)
    }

    public func displayTotal(rate: Decimal) -> Decimal {
        total * rate
    }

    /// The row's unrounded share of the total, or `nil` when the total is not positive.
    public func weight(of row: DashboardRow<Key>) -> Decimal? {
        ratio(of: row, to: basis)
    }

    /// The row's value on the list's basis over the list total on `basis`, or `nil` when that total
    /// is not positive. Exposure's "% of spot" is `ratio(of: row, to: .gross)`: a ratio, not a share.
    public func ratio(of row: DashboardRow<Key>, to basis: DashboardBasis) -> Decimal? {
        let total = totals.value(on: basis)
        return total > 0 ? row.value / total : nil
    }

    /// Visible rows ranked by value, largest first, with ties broken by `tieBreak` (else by order of
    /// appearance). Rows beyond `top` fold into the remainder (F5).
    public func ranked(
        top limit: Int? = nil,
        tieBreak: ((DashboardRow<Key>, DashboardRow<Key>) -> Bool)? = nil) -> RankedDashboardList<Key> {
        let ranked = visibleRows.enumerated().sorted { lhs, rhs in
            if lhs.element.value != rhs.element.value {
                return lhs.element.value > rhs.element.value
            }
            if let tieBreak {
                if tieBreak(lhs.element, rhs.element) {
                    return true
                }
                if tieBreak(rhs.element, lhs.element) {
                    return false
                }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        let shown = limit.map { Array(ranked.prefix(max($0, 0))) } ?? ranked
        let folded = ValuationTotals(ranked.dropFirst(shown.count).flatMap(\.tokens))
        let remainder = folded.value(on: basis) != 0 ? folded : nil
        return RankedDashboardList(basis: basis, rows: shown, remainder: remainder, hidden: hidden, total: total)
    }
}

/// A list as shown: ranked rows, the "Other" remainder and the hidden-balances line, with shares.
public struct RankedDashboardList<Key: Hashable & Sendable>: Equatable, Sendable {
    public let basis: DashboardBasis
    public let rows: [DashboardRow<Key>]
    /// The visible rows beyond the cap; `nil` when they sum to zero on the basis.
    public let remainder: ValuationTotals?
    public let hidden: HiddenBalances
    public let total: Decimal

    public func displayTotal(rate: Decimal) -> Decimal {
        total * rate
    }

    /// The "Other" slice on the list's basis, in the display currency.
    public func displayRemainder(rate: Decimal) -> Decimal? {
        remainder.map { $0.value(on: basis) * rate }
    }

    /// F4 shares of the rows, the remainder and the hidden line, rounded to `fractionDigits` (3 is
    /// 0.1%, 2 is whole percent) so they sum to 100%; `nil` when shares show "—".
    public func shares(fractionDigits: Int = 3) -> ListShares? {
        var values = rows.map(\.value)
        if let remainder {
            values.append(remainder.value(on: basis))
        }
        if !hidden.isEmpty {
            values.append(hidden.value(on: basis))
        }
        guard let rounded = ListShares.rounded(values, fractionDigits: fractionDigits) else { return nil }
        var tail = rounded.dropFirst(rows.count)
        let remainderShare = remainder == nil ? nil : tail.popFirst()
        let hiddenShare = hidden.isEmpty ? nil : tail.popFirst()
        return ListShares(rows: Array(rounded.prefix(rows.count)), remainder: remainderShare, hidden: hiddenShare)
    }
}

/// Displayed shares (F4).
public struct ListShares: Equatable, Sendable {
    public let rows: [Decimal]
    public let remainder: Decimal?
    public let hidden: Decimal?

    public var all: [Decimal] {
        rows + [remainder, hidden].compactMap(\.self)
    }

    /// Each value's share of their sum, rounded to `fractionDigits` (3 is 0.1%, 2 is whole percent)
    /// by largest remainder so the shares sum to exactly 1. Each share is rounded to the nearest
    /// step, then the leftover steps go one each to the rows rounded furthest from their exact
    /// share: a positive leftover to the largest errors, a negative one to the most negative. Ties
    /// go to the larger absolute value, then the earlier row. No share ends a step or more from
    /// exact. `nil` for an empty list or a total that is not positive.
    public static func rounded(_ values: [Decimal], fractionDigits: Int = 3) -> [Decimal]? {
        let total = values.reduce(Decimal.zero, +)
        guard !values.isEmpty, total > 0 else { return nil }

        let stepsInOne = pow(Decimal(10), fractionDigits)
        var steps = values.map { value in
            var share = value / total
            var rounded = Decimal()
            NSDecimalRound(&rounded, &share, fractionDigits, .plain)
            return rounded * stepsInOne
        }
        // The rounding error in steps times the total, which is exact, so equal errors tie.
        let errors = values.indices.map { values[$0] * stepsInOne - steps[$0] * total }
        let residual = stepsInOne - steps.reduce(Decimal.zero, +)
        guard residual != 0 else { return steps.map { $0 / stepsInOne } }

        let order = values.indices.sorted { lhs, rhs in
            if errors[lhs] != errors[rhs] {
                return residual > 0 ? errors[lhs] > errors[rhs] : errors[lhs] < errors[rhs]
            }
            if abs(values[lhs]) != abs(values[rhs]) {
                return abs(values[lhs]) > abs(values[rhs])
            }
            return lhs < rhs
        }
        let step: Decimal = residual > 0 ? 1 : -1
        for index in order.prefix(Int(truncating: abs(residual) as NSDecimalNumber)) {
            steps[index] += step
        }
        return steps.map { $0 / stepsInOne }
    }
}
