import Foundation
import PortuCore

enum AllPositionsFeature {
    static let walletProtocolName = "Wallet"

    /// The page seam: cards, sections and sidebar options from one valuation of the active accounts'
    /// inputs (A7: net basis). A card is Σ its tokens' contributions; a section and a sidebar option
    /// are each Σ their cards, summed in USD and converted once. No row is ever hidden. Cards and
    /// rows sort by value, whatever order the store returns them in (U5).
    static func page(
        _ context: ValuationContext,
        cards infos: [AllPositionsCardInfo],
        filter: AllPositionsFilter) -> AllPositionsPage {
        let valuation = context.valuation()
        let rate = context.usdToDisplayRate
        let tokensByCard = Dictionary(grouping: valuation.tokens, by: \.position.positionId)
        let totalsByCard = valuation.totals(groupedBy: \.position.positionId)
        let cardTotal = { (info: AllPositionsCardInfo) in totalsByCard[info.id] ?? .zero }
        let sum = { (infos: [AllPositionsCardInfo]) in
            infos.map(cardTotal).reduce(ValuationTotals.zero, +).display(rate: rate).net
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
                        AllPositionsCard(
                            id: info.id,
                            title: info.protocolName ?? info.positionType.rawValue.capitalized,
                            chain: info.chain,
                            healthFactor: info.healthFactor,
                            total: cardTotal(info).display(rate: rate).net,
                            rows: (tokensByCard[info.id] ?? []).sorted(by: rowOrder).map { row($0, rate: rate) })
                    }
                    .sorted(by: cardOrder))
            }

        var typeOptions = [AllPositionsTypeOption(type: nil, label: "All", total: valuation.totals.display(rate: rate).net)]
        for type in PositionType.allCases {
            let ofType = infos.filter { $0.positionType == type }
            guard !ofType.isEmpty else { continue }
            typeOptions.append(AllPositionsTypeOption(type: type, label: type.rawValue.capitalized, total: sum(ofType)))
        }

        let protocolOptions = Dictionary(grouping: infos, by: \.protocolId)
            .map { protocolId, infos in
                AllPositionsProtocolOption(
                    filter: protocolId.map(ProtocolFilter.specific) ?? .none,
                    name: protocolId == nil ? walletProtocolName : protocolName(infos),
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

    /// A protocol's option is named after the lowest non-nil protocol name of its positions, as
    /// Platforms names a platform, else "Wallet". The protocol-less option is always "Wallet": a
    /// manual position can carry a name without a protocol ID, and must not rename it.
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

    /// U5: largest total first; ties by position ID.
    private static func cardOrder(_ lhs: AllPositionsCard, _ rhs: AllPositionsCard) -> Bool {
        if lhs.total != rhs.total {
            return lhs.total > rhs.total
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// U5, as Asset Detail orders its rows: contribution descending, so rows that count 0 (not
    /// counted, unpriced, ignored) sit between the supplies and the borrows; ties by symbol, then
    /// token ID.
    private static func rowOrder(_ lhs: ValuedToken, _ rhs: ValuedToken) -> Bool {
        if lhs.contribution != rhs.contribution {
            return lhs.contribution > rhs.contribution
        }
        let order = lhs.token.symbol.localizedStandardCompare(rhs.token.symbol)
        if order != .orderedSame {
            return order == .orderedAscending
        }
        return lhs.tokenId.uuidString < rhs.tokenId.uuidString
    }

    private static func protocolKey(_ filter: ProtocolFilter) -> String {
        if case let .specific(id) = filter {
            return id
        }
        return ""
    }

    /// U4: the row's value is `ValuedToken.rowValue` in the display currency.
    private static func row(_ token: ValuedToken, rate: Decimal) -> AllPositionsRow {
        AllPositionsRow(
            id: token.tokenId,
            role: token.token.role,
            symbol: token.token.symbol,
            amount: token.token.amount,
            state: token.rowState,
            value: token.display(rate: rate).rowValue)
    }
}
