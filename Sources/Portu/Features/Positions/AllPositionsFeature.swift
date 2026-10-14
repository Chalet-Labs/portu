import Foundation
import PortuCore

/// The boundary between SwiftData and All Positions.
///
/// `SyncEngine` deletes and reinserts `Position` rows while SwiftUI may still be evaluating a body,
/// and reading a deleted model's property terminates the process (#103). The page reads every
/// model here, once, at the top of its body pass; only value types cross.
struct AllPositionsProjection: Equatable {
    /// The active accounts' valuation inputs.
    let inputs: [ValuationInput]
    /// Every active position, in query order, including one with no token.
    let cards: [AllPositionsCardInfo]

    @MainActor
    init(_ positions: [Position], categoryResolver: PortfolioCategoryResolver = .defaults) {
        let active = positions.filter { $0.account?.isActive == true }
        self.inputs = ValuationInput.activeAccounts(active.flatMap(\.tokens), categoryResolver: categoryResolver)
        self.cards = active.map { position in
            AllPositionsCardInfo(
                id: position.id,
                positionType: position.positionType,
                protocolId: position.protocolId,
                protocolName: position.protocolName,
                chain: position.chain,
                healthFactor: position.healthFactor)
        }
    }
}

enum AllPositionsFeature {
    static let walletProtocolName = "Wallet"

    /// The page seam: cards, sections and sidebar options from one valuation of the active accounts'
    /// inputs (A7: net basis; a section and a sidebar option are each Σ their cards).
    ///
    /// Transitional: cards and rows still price from `legacyDisplayPrices`, the display-currency
    /// live book keyed by the raw CoinGecko ID, else the sync value; sections and options still sum
    /// each card's sync-time total (A6, today's stored `netUSDValue`).
    static func page(
        _ context: ValuationContext,
        cards infos: [AllPositionsCardInfo],
        filter: AllPositionsFilter,
        legacyDisplayPrices: [String: Decimal] = [:]) -> AllPositionsPage {
        let valuation = context.valuation()
        let rate = context.usdToDisplayRate
        let tokensByCard = Dictionary(grouping: valuation.tokens, by: \.position.positionId)
        let totalsByCard = valuation.totals(groupedBy: \.position.positionId)
        let cardTotal = { (info: AllPositionsCardInfo) in totalsByCard[info.id] ?? .zero }
        let sum = { (infos: [AllPositionsCardInfo]) in
            infos.map(cardTotal).reduce(ValuationTotals.zero, +).display(rate: rate).syncTotal
        }

        let shown = infos.filter(filter.matches)
        let sections = Dictionary(grouping: shown, by: \.positionType)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { type, infos in
                AllPositionsSection(
                    type: type,
                    title: sectionTitle(type),
                    total: sum(infos),
                    cards: infos.map { info in
                        let tokens = tokensByCard[info.id] ?? []
                        return AllPositionsCard(
                            id: info.id,
                            title: info.protocolName ?? info.positionType.rawValue.capitalized,
                            chain: info.chain,
                            healthFactor: info.healthFactor,
                            total: tokens.reduce(Decimal.zero) {
                                $0 + legacySignedValue($1.token, prices: legacyDisplayPrices, rate: rate)
                            },
                            rows: tokens.map { token in
                                AllPositionsRow(
                                    id: token.tokenId,
                                    role: token.token.role,
                                    symbol: token.token.symbol,
                                    amount: token.token.amount,
                                    state: .counted,
                                    value: legacyValue(token.token, prices: legacyDisplayPrices, rate: rate))
                            })
                    })
            }

        var typeOptions = [AllPositionsTypeOption(type: nil, label: "All", total: valuation.totals.display(rate: rate).syncTotal)]
        for type in PositionType.allCases {
            let ofType = infos.filter { $0.positionType == type }
            guard !ofType.isEmpty else { continue }
            typeOptions.append(AllPositionsTypeOption(type: type, label: type.rawValue.capitalized, total: sum(ofType)))
        }

        let protocolOptions = Dictionary(grouping: infos, by: \.protocolId)
            .map { protocolId, infos in
                AllPositionsProtocolOption(
                    filter: protocolId.map(ProtocolFilter.specific) ?? .none,
                    name: protocolName(infos),
                    total: sum(infos))
            }
            .sorted(by: protocolOrder)

        return AllPositionsPage(sections: sections, typeOptions: typeOptions, protocolOptions: protocolOptions)
    }

    static func sectionTitle(_ type: PositionType) -> String {
        switch type {
        case .idle: "Idle"
        case .lending: "Lending"
        case .liquidityPool: "Liquidity Pools"
        case .staking: "Staking"
        case .farming: "Farming"
        case .vesting: "Vesting"
        case .other: "Other"
        }
    }

    /// The lowest non-nil protocol name of the option's positions, as Platforms names a platform
    /// (AGENT-DECIDED 8), else "Wallet".
    private static func protocolName(_ infos: [AllPositionsCardInfo]) -> String {
        infos.compactMap(\.protocolName).min { lhs, rhs in
            let order = lhs.localizedStandardCompare(rhs)
            return order == .orderedSame ? lhs < rhs : order == .orderedAscending
        } ?? walletProtocolName
    }

    /// Largest total first; ties by name, then protocol ID, with the protocol-less option first.
    private static func protocolOrder(_ lhs: AllPositionsProtocolOption, _ rhs: AllPositionsProtocolOption) -> Bool {
        if lhs.total != rhs.total {
            return lhs.total > rhs.total
        }
        let order = lhs.name.localizedStandardCompare(rhs.name)
        if order != .orderedSame {
            return order == .orderedAscending
        }
        return protocolKey(lhs.filter) < protocolKey(rhs.filter)
    }

    private static func protocolKey(_ filter: ProtocolFilter) -> String {
        if case let .specific(id) = filter {
            return id
        }
        return ""
    }

    // MARK: - Transitional

    private static func legacyValue(_ token: TokenEntry, prices: [String: Decimal], rate: Decimal) -> Decimal {
        if let price = token.coinGeckoId.flatMap({ prices[$0] }) {
            return token.amount * price
        }
        return token.usdValue * rate
    }

    private static func legacySignedValue(_ token: TokenEntry, prices: [String: Decimal], rate: Decimal) -> Decimal {
        let value = legacyValue(token, prices: prices, rate: rate)
        return switch token.role {
        case .borrow: -value
        case .reward: 0
        case .balance, .supply, .stake, .lpToken: value
        }
    }
}
