import Foundation

/// The value of a set of tokens on every basis, plus their 24h change.
public struct ValuationTotals: Equatable, Sendable {
    /// Σ positive-role contributions.
    public var gross: Decimal
    /// Σ borrow values, as a positive amount.
    public var debt: Decimal
    /// Σ the tokens' 24h changes (V4) over every token, valued or not (A4). A change, not a value:
    /// `net` is the total it belongs to.
    public var change24h: Decimal
    /// Σ role-signed amounts of counted tokens, ignored ones included. Only meaningful for one asset.
    public var netAmount: Decimal
    /// The raw sync-time total (A6): role-signed `usdValue`, rewards 0, no repricing, no ignore filter.
    public var syncTotal: Decimal

    public static let zero = ValuationTotals(gross: 0, debt: 0, change24h: 0, netAmount: 0, syncTotal: 0)

    public init(gross: Decimal, debt: Decimal, change24h: Decimal, netAmount: Decimal, syncTotal: Decimal) {
        self.gross = gross
        self.debt = debt
        self.change24h = change24h
        self.netAmount = netAmount
        self.syncTotal = syncTotal
    }

    public init(_ tokens: some Sequence<ValuedToken>) {
        self = .zero
        for token in tokens {
            add(token)
        }
    }

    /// Σ contributions: gross − debt (A1, A2).
    public var net: Decimal {
        gross - debt
    }

    /// `change / (total − change)`, or `nil` (shown as "—") unless the prior total is positive.
    public var changePercentage: Decimal? {
        Self.changePercentage(change: change24h, total: net)
    }

    public static func changePercentage(change: Decimal, total: Decimal) -> Decimal? {
        let prior = total - change
        guard prior > 0 else { return nil }
        return change / prior
    }

    public func value(on basis: DashboardBasis) -> Decimal {
        switch basis {
        case .gross: gross
        case .debt: debt
        case .net, .positiveNet: net
        }
    }

    /// Money in the display currency. Amounts and percentages are unchanged.
    public func display(rate: Decimal) -> ValuationTotals {
        ValuationTotals(
            gross: gross * rate,
            debt: debt * rate,
            change24h: change24h * rate,
            netAmount: netAmount,
            syncTotal: syncTotal * rate)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        ValuationTotals(
            gross: lhs.gross + rhs.gross,
            debt: lhs.debt + rhs.debt,
            change24h: lhs.change24h + rhs.change24h,
            netAmount: lhs.netAmount + rhs.netAmount,
            syncTotal: lhs.syncTotal + rhs.syncTotal)
    }

    private mutating func add(_ token: ValuedToken) {
        let role = token.token.role
        if role.isPositive {
            gross += token.contribution
        } else if role.isBorrow {
            debt += token.value
        }
        change24h += token.change24h
        syncTotal += role.signed(token.token.usdValue)
        if token.isCounted {
            netAmount += role.isBorrow ? -token.token.amount : token.token.amount
        }
    }
}

/// The Overview Idle / Deployed / Debt cards (A3). Idle + Deployed − Debt = net total.
public struct SummaryCards: Equatable, Sendable {
    public struct Idle: Equatable, Sendable {
        public var stablecoinsAndFiat: Decimal = 0
        public var majors: Decimal = 0
        public var tokensAndMemecoins: Decimal = 0

        public var total: Decimal {
            stablecoinsAndFiat + majors + tokensAndMemecoins
        }
    }

    public struct Deployed: Equatable, Sendable {
        public var lending: Decimal = 0
        public var staked: Decimal = 0
        /// Farming and liquidity pools.
        public var yield: Decimal = 0
        /// Vesting and other positions.
        public var other: Decimal = 0

        public var total: Decimal {
            lending + staked + yield + other
        }
    }

    public var idle = Idle()
    public var deployed = Deployed()
    /// "Borrowed": the debt of A2.
    public var debt: Decimal = 0

    init(_ tokens: [ValuedToken]) {
        for token in tokens {
            add(token.contribution, of: token.token, in: token.position.positionType)
        }
    }

    /// The same split over the raw sync-time values (A6), for snapshot recording (N1): every amount,
    /// no repricing, rewards 0. Idle + Deployed − Debt equals `PortfolioValuation.syncTimeTotal`.
    public static func syncTime(
        of inputs: some Sequence<ValuationInput>,
        excludingIgnoredIn overrides: [TokenPricingOverrideSnapshot] = []) -> SummaryCards {
        let ignored = TokenPricingOverrideFeature.ignoredAssetIds(overrides)
        var cards = SummaryCards()
        for input in inputs where !ignored.contains(input.token.assetId) {
            cards.add(input.token.role.signed(input.token.usdValue), of: input.token, in: input.position.positionType)
        }
        return cards
    }

    private init() {}

    private init(idle: Idle, deployed: Deployed, debt: Decimal) {
        self.idle = idle
        self.deployed = deployed
        self.debt = debt
    }

    public func display(rate: Decimal) -> SummaryCards {
        SummaryCards(
            idle: Idle(
                stablecoinsAndFiat: idle.stablecoinsAndFiat * rate,
                majors: idle.majors * rate,
                tokensAndMemecoins: idle.tokensAndMemecoins * rate),
            deployed: Deployed(
                lending: deployed.lending * rate,
                staked: deployed.staked * rate,
                yield: deployed.yield * rate,
                other: deployed.other * rate),
            debt: debt * rate)
    }

    /// Positive roles land on a card by position type; a borrow's negative contribution is debt.
    private mutating func add(_ contribution: Decimal, of token: TokenEntry, in positionType: PositionType) {
        if token.role.isBorrow {
            debt -= contribution
            return
        }
        guard token.role.isPositive else { return }

        switch positionType {
        case .idle:
            let category = token.portfolioCategory
            if category.semanticRole == .stablecoin || category.semanticRole == .fiat {
                idle.stablecoinsAndFiat += contribution
            } else if PortfolioCategoryDefaults.majorCategoryIDs.contains(category.id) {
                idle.majors += contribution
            } else {
                idle.tokensAndMemecoins += contribution
            }
        case .lending:
            deployed.lending += contribution
        case .staking:
            deployed.staked += contribution
        case .farming, .liquidityPool:
            deployed.yield += contribution
        case .vesting, .other:
            deployed.other += contribution
        }
    }
}

/// The unit price, source and 24h fraction a row shows (V5).
public struct RowPricing: Equatable, Sendable {
    public let price: Decimal?
    public let source: ValuationSource?
    public let fraction24h: Decimal?

    public static let none = RowPricing(price: nil, source: nil, fraction24h: nil)

    public init(price: Decimal?, source: ValuationSource?, fraction24h: Decimal?) {
        self.price = price
        self.source = source
        self.fraction24h = fraction24h
    }

    /// Price = Σ value ÷ Σ amount over the counted, valued tokens. Source and fraction come from the
    /// lead token: the largest value, then source order, lowest asset ID, lowest price ID.
    public init(tokens: some Sequence<ValuedToken>) {
        let priced = tokens.filter { $0.isCounted && $0.isValued }
        let amount = priced.reduce(Decimal.zero) { $0 + $1.token.amount }
        guard amount > 0, let lead = priced.min(by: Self.leads) else {
            self = .none
            return
        }
        self.init(
            price: priced.reduce(Decimal.zero) { $0 + $1.value } / amount,
            source: lead.source,
            fraction24h: lead.source == .manual ? nil : lead.fraction24h)
    }

    public func display(rate: Decimal) -> RowPricing {
        RowPricing(price: price.map { $0 * rate }, source: source, fraction24h: fraction24h)
    }

    private static func leads(_ lhs: ValuedToken, _ rhs: ValuedToken) -> Bool {
        if lhs.value != rhs.value {
            return lhs.value > rhs.value
        }
        if lhs.source != rhs.source {
            return lhs.source < rhs.source
        }
        let lhsAsset = lhs.token.assetId.uuidString
        let rhsAsset = rhs.token.assetId.uuidString
        if lhsAsset != rhsAsset {
            return lhsAsset < rhsAsset
        }
        return (lhs.priceID ?? "") < (rhs.priceID ?? "")
    }
}
