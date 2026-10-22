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

/// A tab as shown: its position groups, each ending with its own hidden-balances line, then one line
/// for the groups that have no visible row (S3). Money is in the display currency, and the total and
/// change are the module's aggregates over the tab on its basis.
struct OverviewPositionTabData: Equatable {
    let groups: [OverviewPositionGroupData]
    let basis: DashboardBasis
    /// The rows of groups with no visible row; `nil` when there are none.
    let hidden: HiddenBalances?
    /// Every group plus the tab's hidden line; for Key Changes, the shown rows.
    let total: Decimal
    let change24h: Decimal

    /// A tab whose rows are all hidden still shows its hidden line instead of the empty message.
    var showsEmptyState: Bool {
        groups.isEmpty && hidden == nil
    }
}

/// The Overview position tabs' seam over value types (#103, #124).
///
/// `SyncEngine` deletes and reinserts `Position` rows on the main actor while SwiftUI
/// may still be evaluating a body. Reading a deleted model's property trips a
/// SwiftData assertion that terminates the process, which is the 1.9.0 crash in
/// issue #103. No view body reads a model now: `PortfolioProjector` is the only reader, on its own
/// context, and only the value types it projects (the holdings and each position's
/// `OverviewPositionMeta`) reach this type and the reducer state.
enum OverviewPositionProjection {
    static let keyChangeLimit = 20

    /// The position-tab seam: one tab of the active-account inputs.
    ///
    /// The tab keeps the valued tokens it admits from the context's valuation, which equals valuing
    /// those inputs alone (`PortfolioValuation.restricted`), so the read model values the holdings
    /// once for every tab.
    static func tab(
        _ tab: OverviewPositionTab,
        context: ValuationContext,
        positions: [UUID: OverviewPositionMeta]) -> OverviewPositionTabData {
        let admitted = Set(context.inputs.lazy.filter { input in
            tab.admits(input.position.positionType)
                && tab.admits(input.token.role)
                && tab.admits(input.token.portfolioCategory)
                && positions[input.position.positionId] != nil
        }.map(\.tokenId))
        let valuation = context.valuation().restricted { admitted.contains($0.tokenId) }
        let rate = context.usdToDisplayRate

        switch tab {
        case .keyChanges:
            // Exempt in A7: the groups and the tab total the shown movers only.
            let basis = DashboardBasis.net
            let movers = valuation.keyChanges(settings: context.settings, limit: keyChangeLimit)
            let groups = grouped(movers, positions: positions).map { position, tokens in
                let totals = ValuationTotals(tokens)
                return OverviewPositionGroupData(
                    position: position,
                    tokens: tokens.map { row($0, basis: basis, rate: rate) },
                    basis: basis,
                    hidden: nil,
                    value: totals.value(on: basis) * rate,
                    change24h: onBasis(totals.change24h, basis) * rate)
            }
            let totals = ValuationTotals(movers)
            return OverviewPositionTabData(
                groups: groups,
                basis: basis,
                hidden: nil,
                total: totals.value(on: basis) * rate,
                change24h: onBasis(totals.change24h, basis) * rate)
        case .idleStables, .idleMajors:
            return filtered(valuation, basis: .net, positions: positions, context: context)
        case .borrowing:
            return filtered(valuation, basis: .debt, positions: positions, context: context)
        }
    }

    // MARK: - Filtered tabs

    /// One display-filtered list per position group, so each group ends with its own hidden line. A
    /// group with no visible row gets no card; its rows fold into the tab's line. A group's total and
    /// change are its list's, which cover its hidden rows; the tab's are the valuation's, since
    /// `valuation` holds exactly the tab's tokens.
    private static func filtered(
        _ valuation: PortfolioValuation,
        basis: DashboardBasis,
        positions: [UUID: OverviewPositionMeta],
        context: ValuationContext) -> OverviewPositionTabData {
        let rate = context.usdToDisplayRate
        var groups: [OverviewPositionGroupData] = []
        var folded: [ValuedToken] = []

        for (position, tokens) in grouped(valuation.tokens, positions: positions) {
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
                value: list.total * rate,
                change24h: onBasis(list.totals.change24h, basis) * rate))
        }

        let footer = DashboardList(folded, basis: basis, settings: context.settings, groupedBy: \.tokenId).hidden
        return OverviewPositionTabData(
            groups: groups,
            basis: basis,
            hidden: footer.isEmpty ? nil : footer.display(rate: rate),
            total: valuation.totals.value(on: basis) * rate,
            change24h: onBasis(valuation.totals.change24h, basis) * rate)
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
    /// its debt, and its change is positive when the debt grows. The holding tabs admit positive
    /// roles only, so on their net basis a row's value is its gross value.
    private static func row(_ token: ValuedToken, basis: DashboardBasis, rate: Decimal) -> OverviewPositionTokenData {
        let shown = token.display(rate: rate)
        return OverviewPositionTokenData(
            id: shown.tokenId,
            entry: shown.token,
            price: shown.token.amount > 0 ? shown.value / shown.token.amount : 0,
            value: shown.value,
            change24h: onBasis(shown.change24h, basis))
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
