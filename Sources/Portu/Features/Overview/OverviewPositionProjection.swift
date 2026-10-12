import Foundation
import PortuCore

enum OverviewPositionTab: String, CaseIterable {
    case keyChanges = "Key Changes"
    case idleStables = "Idle Stables"
    case idleMajors = "Idle BTC / ETH / SOL"
    case borrowing = "Borrowing"

    /// Shown when the tab resolves to no positions.
    var emptyMessage: String {
        switch self {
        case .keyChanges: "No key changes"
        case .idleStables: "No idle stables"
        case .idleMajors: "No idle BTC / ETH / SOL"
        case .borrowing: "No borrowing"
        }
    }
}

/// Valuation inputs for the position tabs, with the position metadata the groups show.
struct OverviewPositionInputs {
    let inputs: [ValuationInput]
    let positions: [UUID: OverviewPositionMeta]
}

/// A tab as shown: its position groups, each ending with its own hidden-balances line, then one line
/// for the groups that have no visible row (S3). Totals and changes are on the tab's basis.
struct OverviewPositionTabData: Equatable {
    let groups: [OverviewPositionGroupData]
    var basis: DashboardBasis = .gross
    /// The rows of groups with no visible row, in the display currency; `nil` when there are none.
    var hidden: HiddenBalances?
    /// Those rows' 24h change on the tab's basis.
    var hiddenChange24h: Decimal = 0

    var total: Decimal {
        groups.reduce(Decimal.zero) { $0 + $1.value } + (hidden?.value(on: basis) ?? 0)
    }

    var change24h: Decimal {
        groups.reduce(Decimal.zero) { $0 + $1.change24h } + hiddenChange24h
    }

    /// A tab whose rows are all hidden still shows its hidden line instead of the empty message.
    var showsEmptyState: Bool {
        groups.isEmpty && hidden == nil
    }
}

/// The boundary between SwiftData and the Overview position UI.
///
/// `SyncEngine` deletes and reinserts `Position` rows on the main actor while SwiftUI
/// may still be evaluating a body. Reading a deleted model's property trips a
/// SwiftData assertion that terminates the process, which is the 1.9.0 crash in
/// issue #103. Every model read for the position tabs happens in this type, and only
/// value types cross the boundary, so no view body can observe a deleted model.
enum OverviewPositionProjection {
    static let keyChangeLimit = 20

    /// The position-tab seam: one tab of the active-account inputs.
    ///
    /// Only the selected tab is resolved, and only the inputs it admits are valued.
    static func tab(
        _ tab: OverviewPositionTab,
        context: OverviewValuationContext,
        positions: [UUID: OverviewPositionMeta]) -> OverviewPositionTabData {
        let admitted = context.inputs.filter { input in
            tab.admits(input.position.positionType)
                && tab.admits(input.token.role)
                && tab.admits(input.token.portfolioCategory)
                && positions[input.position.positionId] != nil
        }
        let valuation = context.restricted(to: admitted).valuation()

        switch tab {
        case .keyChanges:
            let movers = valuation.keyChanges(settings: context.settings, limit: keyChangeLimit)
            let groups = grouped(movers, positions: positions).map { position, tokens in
                OverviewPositionGroupData(
                    position: position,
                    tokens: tokens.map { row($0, basis: .gross, rate: context.usdToDisplayRate) })
            }
            return OverviewPositionTabData(groups: groups)
        case .idleStables, .idleMajors:
            return filtered(valuation.tokens, basis: .gross, positions: positions, context: context)
        case .borrowing:
            return filtered(valuation.tokens, basis: .debt, positions: positions, context: context)
        }
    }

    // MARK: - Model boundary

    /// The only place position models are read: the active-account valuation inputs `tab` can show
    /// and the metadata of the positions they belong to.
    ///
    /// Work is discarded as early as possible: positions are rejected on their type before any
    /// token is projected, tokens on their role before they become inputs, and metadata is
    /// faulted only for positions that still contribute an input.
    static func inputs(
        from positions: [Position],
        for tab: OverviewPositionTab,
        categoryResolver: PortfolioCategoryResolver) -> OverviewPositionInputs {
        let tokens = positions
            .filter { tab.admits($0.positionType) }
            .flatMap(\.tokens)
            .filter { tab.admits($0.role) }
        let inputs = ValuationInput.activeAccounts(tokens, categoryResolver: categoryResolver)
        let positionIDs = Set(inputs.map(\.position.positionId))
        var meta: [UUID: OverviewPositionMeta] = [:]
        for position in positions where positionIDs.contains(position.id) {
            meta[position.id] = OverviewPositionMeta(
                id: position.id,
                title: position.protocolName ?? position.account?.name ?? "Wallet",
                positionType: position.positionType,
                chain: position.chain)
        }
        return OverviewPositionInputs(inputs: inputs, positions: meta)
    }

    // MARK: - Filtered tabs

    /// One display-filtered list per position group, so each group ends with its own hidden line. A
    /// group with no visible row gets no card; its rows fold into the tab's line.
    private static func filtered(
        _ tokens: [ValuedToken],
        basis: DashboardBasis,
        positions: [UUID: OverviewPositionMeta],
        context: OverviewValuationContext) -> OverviewPositionTabData {
        let rate = context.usdToDisplayRate
        var groups: [OverviewPositionGroupData] = []
        var folded: [ValuedToken] = []

        for (position, tokens) in grouped(tokens, positions: positions) {
            let list = DashboardList(tokens, basis: basis, settings: context.settings, groupedBy: \.tokenId)
            let visible = list.visibleRows.flatMap(\.tokens)
            guard !visible.isEmpty else {
                folded += tokens
                continue
            }
            groups.append(OverviewPositionGroupData(
                position: position,
                tokens: visible.map { row($0, basis: basis, rate: rate) },
                basis: basis,
                hidden: list.hidden.isEmpty ? nil : list.hidden.display(rate: rate),
                hiddenChange24h: hiddenChange24h(list, basis: basis) * rate))
        }

        let footer = DashboardList(folded, basis: basis, settings: context.settings, groupedBy: \.tokenId)
        return OverviewPositionTabData(
            groups: groups,
            basis: basis,
            hidden: footer.hidden.isEmpty ? nil : footer.hidden.display(rate: rate),
            hiddenChange24h: hiddenChange24h(footer, basis: basis) * rate)
    }

    /// Groups tokens by owning position, preserving first-appearance order.
    private static func grouped(
        _ tokens: [ValuedToken],
        positions: [UUID: OverviewPositionMeta]) -> [(OverviewPositionMeta, [ValuedToken])] {
        var order: [UUID] = []
        var grouped: [UUID: [ValuedToken]] = [:]
        for token in tokens {
            let id = token.position.positionId
            if grouped[id] == nil {
                order.append(id)
            }
            grouped[id, default: []].append(token)
        }
        return order.compactMap { id in
            guard let position = positions[id], let tokens = grouped[id] else { return nil }
            return (position, tokens)
        }
    }

    /// A token row in the display currency. Value and change are on the tab's basis: a borrow shows
    /// its debt, and its change is positive when the debt grows.
    private static func row(_ token: ValuedToken, basis: DashboardBasis, rate: Decimal) -> OverviewPositionTokenData {
        let price = token.token.amount > 0 ? token.value / token.token.amount : 0
        return OverviewPositionTokenData(
            id: token.tokenId,
            entry: token.token,
            price: price * rate,
            value: token.value * rate,
            change24h: onBasis(token.change24h, basis) * rate)
    }

    /// The hidden rows' 24h change, in USD, on the list's basis.
    private static func hiddenChange24h(_ list: DashboardList<UUID>, basis: DashboardBasis) -> Decimal {
        list.rows
            .filter { $0.status.isDashboardRow && !$0.isVisible }
            .reduce(Decimal.zero) { $0 + onBasis($1.totals.change24h, basis) }
    }

    /// A net change (a borrow's contribution falls as its debt grows) expressed on `basis`.
    private static func onBasis(_ netChange: Decimal, _ basis: DashboardBasis) -> Decimal {
        basis == .debt ? -netChange : netChange
    }
}

private extension OverviewPositionTab {
    /// Idle tabs show idle positions only; the other tabs look at every position.
    func admits(_ positionType: PositionType) -> Bool {
        switch self {
        case .idleStables, .idleMajors: positionType == .idle
        case .keyChanges, .borrowing: true
        }
    }

    /// Borrowing shows borrows; every other tab shows positive roles.
    func admits(_ role: TokenRole) -> Bool {
        switch self {
        case .borrowing: role.isBorrow
        case .keyChanges, .idleStables, .idleMajors: role.isPositive
        }
    }

    /// Idle Stables shows stablecoins and Idle BTC / ETH / SOL the majors.
    func admits(_ category: PortfolioCategorySnapshot) -> Bool {
        switch self {
        case .idleStables: category.semanticRole == .stablecoin
        case .idleMajors: PortfolioCategoryDefaults.majorCategoryIDs.contains(category.id)
        case .keyChanges, .borrowing: true
        }
    }
}
