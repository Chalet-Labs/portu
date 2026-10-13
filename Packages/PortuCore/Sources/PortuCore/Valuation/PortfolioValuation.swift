import Foundation

/// Where a token sits: the fields screens group by (card, section, account, chain, protocol).
public struct PositionContext: Hashable, Sendable {
    public let positionId: UUID
    public let positionType: PositionType
    public let accountId: UUID?
    public let chain: Chain?
    public let protocolId: String?

    public init(
        positionId: UUID,
        positionType: PositionType,
        accountId: UUID? = nil,
        chain: Chain? = nil,
        protocolId: String? = nil) {
        self.positionId = positionId
        self.positionType = positionType
        self.accountId = accountId
        self.chain = chain
        self.protocolId = protocolId
    }
}

/// A token plus its position context: the only thing the module values.
public struct ValuationInput: Equatable, Sendable {
    /// The `PositionToken` ID: row identity for token-level lists, distinct even when a looped
    /// position holds one asset as both supply and borrow.
    public let tokenId: UUID
    public let token: TokenEntry
    public let position: PositionContext

    public init(tokenId: UUID, token: TokenEntry, position: PositionContext) {
        self.tokenId = tokenId
        self.token = token
        self.position = position
    }
}

/// Which rule of V1 decided a token's value. The declaration order is the V5 tie-break order.
public enum ValuationSource: Int, Comparable, Sendable {
    case manual
    case live
    case close
    case sync
    case unpriced
    case ignored

    public var isValued: Bool {
        self <= .sync
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One token's valuation, in USD.
public struct ValuedToken: Equatable, Sendable {
    public let tokenId: UUID
    public let token: TokenEntry
    public let position: PositionContext
    /// The price ID the token resolved to; `nil` for a manual price or a token with no ID.
    public let priceID: String?
    public let source: ValuationSource
    /// Unsigned worth.
    public let value: Decimal
    /// `value` signed by role: + for positive roles, − for borrows, 0 for rewards.
    public let contribution: Decimal
    /// The merged 24h fraction of the price ID; `nil` unless the source is live, close or sync.
    public let fraction24h: Decimal?
    public let change24h: Decimal
    /// The asset's `alwaysShow`; always false for an ignored asset.
    public let alwaysShow: Bool

    public var isIgnored: Bool {
        source == .ignored
    }

    public var isValued: Bool {
        source.isValued
    }

    /// A positive or borrow role with a positive amount. Ignore and source do not change it.
    public var isCounted: Bool {
        (token.role.isPositive || token.role.isBorrow) && token.amount > 0
    }

    /// How a token-level row shows this token (All Positions, Asset Detail, the Token Settings
    /// badges).
    public var rowState: TokenRowState {
        isIgnored ? .counted : .ignored
    }

    /// What polling ranks by and backfill gates on (S12): the value, or `|usdValue|` when the value
    /// is 0. Ignored tokens are never candidates.
    public var selectionValue: Decimal? {
        guard !isIgnored else { return nil }
        return value != 0 ? value : abs(token.usdValue)
    }

    public func display(rate: Decimal) -> ValuedToken {
        ValuedToken(
            tokenId: tokenId,
            token: token,
            position: position,
            priceID: priceID,
            source: source,
            value: value * rate,
            contribution: contribution * rate,
            fraction24h: fraction24h,
            change24h: change24h * rate,
            alwaysShow: alwaysShow)
    }
}

/// The state of a token-level row. The first match wins.
public enum TokenRowState: Sendable {
    /// The asset is ignored: no value, whatever the role or price.
    case ignored
    /// A reward or an amount ≤ 0. The row still shows the unsigned value, muted; it counts 0.
    case notCounted
    /// Counted, but with no price.
    case unpriced
    /// Counted and valued; the row shows the signed contribution.
    case counted
}

/// Values every input once (V1–V4) and answers every aggregate from those values. Everything is in
/// USD; convert with `display(rate:)` on a result, after any display filtering.
public struct PortfolioValuation: Equatable, Sendable {
    public let tokens: [ValuedToken]
    /// Net, gross, debt and change over every token (A1, A2, A4).
    public let totals: ValuationTotals

    public init(
        inputs: [ValuationInput],
        market: MarketPrices,
        overrides: [TokenPricingOverrideSnapshot] = [],
        mappings: [TokenIdentityMappingSnapshot] = []) {
        let overrideMap = TokenPricingOverrideFeature.overridesByAssetId(overrides)
        let mappingMap = TokenIdentityMappingFeature.mappingsByIdentity(mappings)
        let tokens = inputs.map { input in
            Self.value(
                input,
                override: overrideMap[input.token.assetId],
                mappings: mappingMap,
                market: market)
        }
        self.tokens = tokens
        self.totals = ValuationTotals(tokens)
    }

    public func totals(where isIncluded: (ValuedToken) -> Bool) -> ValuationTotals {
        ValuationTotals(tokens.lazy.filter(isIncluded))
    }

    /// Totals per caller key: cards by position, sections by protocol or type, balances by account.
    public func totals<Key: Hashable>(groupedBy key: (ValuedToken) -> Key) -> [Key: ValuationTotals] {
        Dictionary(grouping: tokens, by: key).mapValues { ValuationTotals($0) }
    }

    /// Idle / Deployed / Debt (A3). Rows are fixed and never display-filtered.
    public var summaryCards: SummaryCards {
        SummaryCards(tokens)
    }

    /// The Key Changes tab (F5): counted positive-role tokens that the filter shows on their own,
    /// with a non-zero change, largest |change| first, ties by symbol.
    public func keyChanges(settings: TokenDashboardSettings, limit: Int = 20) -> [ValuedToken] {
        let candidates = tokens.enumerated().filter { _, token in
            token.token.role.isPositive
                && token.change24h != 0
                && RowClassification([token], settings: settings).isVisible
        }
        let ranked = candidates.sorted { lhs, rhs in
            let lhsChange = abs(lhs.element.change24h)
            let rhsChange = abs(rhs.element.change24h)
            if lhsChange != rhsChange {
                return lhsChange > rhsChange
            }
            if lhs.element.token.symbol != rhs.element.token.symbol {
                return lhs.element.token.symbol < rhs.element.token.symbol
            }
            return lhs.offset < rhs.offset
        }
        return ranked.prefix(max(limit, 0)).map(\.element)
    }

    /// The sync-time total (A6): role-signed raw `usdValue`, rewards 0, whatever the amount, with no
    /// repricing. Pass overrides to leave ignored assets out, as snapshot recording does (N1).
    public static func syncTimeTotal(
        of tokens: some Sequence<TokenEntry>,
        excludingIgnoredIn overrides: [TokenPricingOverrideSnapshot] = []) -> Decimal {
        let ignored = TokenPricingOverrideFeature.ignoredAssetIds(overrides)
        return tokens.reduce(Decimal.zero) { total, token in
            ignored.contains(token.assetId) ? total : total + token.role.signed(token.usdValue)
        }
    }

    // MARK: - Per-token valuation

    private static let plausibleRatio = Decimal(sign: .plus, exponent: -2, significand: 1) ... 100

    private static func value(
        _ input: ValuationInput,
        override: TokenPricingOverrideSnapshot?,
        mappings: [OnchainTokenIdentity: TokenIdentityMappingSnapshot],
        market: MarketPrices) -> ValuedToken {
        let token = input.token
        let priceID = TokenPricingOverrideFeature.resolvedPriceID(
            token: token,
            override: override,
            mappingsByIdentity: mappings)
        let (source, value) = price(token, priceID: priceID, override: override, market: market)
        let contribution = token.role.signed(value)
        let fraction = source.isValued && source != .manual ? priceID.flatMap { market.changes24h[$0] } : nil

        return ValuedToken(
            tokenId: input.tokenId,
            token: token,
            position: input.position,
            priceID: priceID,
            source: source,
            value: value,
            contribution: contribution,
            fraction24h: fraction,
            change24h: change(of: contribution, fraction: fraction),
            alwaysShow: override?.alwaysShow == true && override?.isIgnored != true)
    }

    /// V1, in order: ignored, no amount, manual, live, newer-of close and sync, unpriced.
    private static func price(
        _ token: TokenEntry,
        priceID: String?,
        override: TokenPricingOverrideSnapshot?,
        market: MarketPrices) -> (ValuationSource, Decimal) {
        if override?.isIgnored == true {
            return (.ignored, 0)
        }
        guard token.amount > 0 else { return (.unpriced, 0) }
        if let manual = TokenPricingOverrideFeature.sanitizedManualPrice(override?.manualPriceUSD) {
            return (.manual, token.amount * manual)
        }
        if let priceID, let live = market.liveUSD[priceID], live > 0 {
            return isPlausible(live, priceID: priceID, token: token) ? (.live, token.amount * live) : (.unpriced, 0)
        }

        let close = priceID.flatMap { market.closesUSD[$0] }.flatMap { $0.price > 0 ? $0 : nil }
        let hasSyncValue = token.usdValue != 0
        if let close, let priceID, !hasSyncValue || isNewer(close, than: token.syncedAt) {
            return isPlausible(close.price, priceID: priceID, token: token)
                ? (.close, token.amount * close.price)
                : (.unpriced, 0)
        }
        return hasSyncValue ? (.sync, abs(token.usdValue)) : (.unpriced, 0)
    }

    /// A close carries no intraday time, so it beats the sync value only on a later UTC day.
    private static func isNewer(_ close: HistoricalClose, than syncedAt: Date?) -> Bool {
        guard let syncedAt else { return true }
        return close.day > HistoricalPriceCalendar.utcStartOfDay(for: syncedAt)
    }

    /// V3: onchain prices must land within 1/100 to 100× of the sync value. Both sides are USD.
    private static func isPlausible(_ price: Decimal, priceID: String, token: TokenEntry) -> Bool {
        guard OnchainTokenIdentity(historicalPriceID: priceID) != nil else { return true }
        let reference = abs(token.usdValue)
        guard reference > 0 else { return true }
        return plausibleRatio.contains(token.amount * price / reference)
    }

    /// V4: the move against the price 24h ago, `contribution × p / (1 + p)`.
    private static func change(of contribution: Decimal, fraction: Decimal?) -> Decimal {
        guard let fraction, contribution != 0, 1 + fraction > 0 else { return 0 }
        return contribution * fraction / (1 + fraction)
    }
}

extension TokenRole {
    /// + for positive roles, − for borrows, 0 for rewards (V2).
    func signed(_ value: Decimal) -> Decimal {
        if isPositive {
            return value
        }
        return isBorrow ? -value : 0
    }
}
