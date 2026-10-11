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

/// Pricing and visibility inputs, gathered once per render pass.
struct OverviewPositionContext {
    let prices: [String: Decimal]
    let changes24h: [String: Decimal]
    let overrideMap: [UUID: TokenPricingOverrideSnapshot]
    let mappingMap: [OnchainTokenIdentity: TokenIdentityMappingSnapshot]
    let categoryResolver: PortfolioCategoryResolver
    let dashboardSettings: TokenDashboardSettings
    let fallbackUSDToDisplayRate: Decimal
}

/// Valuation inputs for the position tabs, with the position metadata the groups show.
struct OverviewPositionInputs {
    let inputs: [ValuationInput]
    let positions: [UUID: OverviewPositionMeta]
}

/// A tab as shown: its position groups, each ending with its own hidden-balances line.
struct OverviewPositionTabData: Equatable {
    let groups: [OverviewPositionGroupData]

    var total: Decimal {
        groups.reduce(Decimal.zero) { $0 + $1.value }
    }

    var change24h: Decimal {
        groups.reduce(Decimal.zero) { $0 + $1.change24h }
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

    /// Resolves a single tab into renderable value data.
    ///
    /// Only the selected tab is resolved: a body evaluation costs one projection pass
    /// rather than filtering every token for every tab.
    static func groups(
        for tab: OverviewPositionTab,
        positions: [Position],
        context: OverviewPositionContext) -> [OverviewPositionGroupData] {
        groups(
            for: tab,
            projected: inputs(from: positions, for: tab, categoryResolver: context.categoryResolver),
            context: context)
    }

    /// The position-tab seam: one tab of the active-account inputs.
    static func tab(
        _ tab: OverviewPositionTab,
        context valuation: OverviewValuationContext,
        positions: [UUID: OverviewPositionMeta]) -> OverviewPositionTabData {
        let context = OverviewPositionContext(
            prices: valuation.prices.displayPrices,
            changes24h: valuation.prices.displayChanges24h,
            overrideMap: TokenSettingsFeature.overridesByAssetId(valuation.overrides),
            mappingMap: TokenIdentityMappingFeature.mappingsByIdentity(valuation.mappings),
            // The inputs arrive categorised; the resolver only serves the `Position` entry point.
            categoryResolver: .defaults,
            dashboardSettings: valuation.settings,
            fallbackUSDToDisplayRate: valuation.usdToDisplayRate)
        let groups = groups(
            for: tab,
            projected: OverviewPositionInputs(inputs: valuation.inputs, positions: positions),
            context: context)
        return OverviewPositionTabData(groups: groups)
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

    private static func groups(
        for tab: OverviewPositionTab,
        projected: OverviewPositionInputs,
        context: OverviewPositionContext) -> [OverviewPositionGroupData] {
        switch tab {
        case .keyChanges:
            keyChangeGroups(projected, context: context)
        case .idleStables:
            idleGroups(.idleStables, projected, context: context) { entry in
                entry.portfolioCategory.semanticRole == .stablecoin
            }
        case .idleMajors:
            idleGroups(.idleMajors, projected, context: context) { entry in
                PortfolioCategoryDefaults.majorCategoryIDs.contains(entry.portfolioCategory.id)
            }
        case .borrowing:
            borrowingGroups(projected, context: context)
        }
    }

    /// Inputs are rejected on the tab's position types and roles before their entry is mapped, and
    /// each surviving token is mapped once. The seam can be fed every active input, as the T2 specs
    /// do, so this repeats the model boundary's rejection.
    private static func projectedTokens(
        _ projected: OverviewPositionInputs,
        for tab: OverviewPositionTab,
        context: OverviewPositionContext,
        including isIncluded: (TokenEntry) -> Bool) -> [ProjectedToken] {
        projected.inputs.compactMap { input -> ProjectedToken? in
            guard
                tab.admits(input.position.positionType),
                tab.admits(input.token.role),
                let meta = projected.positions[input.position.positionId]
            else { return nil }
            let entry = tokenEntry(for: input.token, context: context)
            guard isIncluded(entry) else { return nil }
            return ProjectedToken(id: input.tokenId, entry: entry, position: meta)
        }
    }

    /// The asset's own CoinGecko ID, else the identity-mapped one.
    private static func tokenEntry(
        for token: TokenEntry,
        context: OverviewPositionContext) -> TokenEntry {
        let coinGeckoId = OverviewWatchlistStore.normalizedID(token.coinGeckoId)
            ?? TokenIdentityMappingFeature.mappedCoinGeckoID(
                for: token.onchainIdentity,
                mappingsByIdentity: context.mappingMap)
        guard coinGeckoId != token.coinGeckoId else { return token }
        return TokenSettingsFeature.tokenEntry(from: token, coinGeckoId: coinGeckoId, usdValue: token.usdValue)
    }

    // MARK: - Tabs

    /// The biggest movers: change-visible positive tokens ranked by absolute 24h
    /// change, capped at `keyChangeLimit` and grouped by position.
    private static func keyChangeGroups(
        _ projected: OverviewPositionInputs,
        context: OverviewPositionContext) -> [OverviewPositionGroupData] {
        // Ranking needs each candidate's change, so it is computed here and again for
        // the surviving `keyChangeLimit` tokens when their row data is built.
        let ranked = projectedTokens(projected, for: .keyChanges, context: context) { entry in
            isChangeVisible(entry, context: context)
        }
        .compactMap { token -> (token: ProjectedToken, change: Decimal)? in
            let change = change24h(token.entry, context: context)
            guard change != 0 else { return nil }
            return (token, change)
        }
        .sorted {
            OverviewPriceChangeFeature.isOrderedByChangeMagnitude(
                lhsChange: $0.change,
                lhsSymbol: $0.token.entry.symbol,
                rhsChange: $1.change,
                rhsSymbol: $1.token.entry.symbol)
        }
        .prefix(keyChangeLimit)
        .map(\.token)

        return groups(from: Array(ranked), context: context)
    }

    /// Idle tokens the dashboard shows and whose resolved category satisfies
    /// `predicate` — stablecoins for Idle Stables, majors for Idle BTC / ETH / SOL.
    private static func idleGroups(
        _ tab: OverviewPositionTab,
        _ projected: OverviewPositionInputs,
        context: OverviewPositionContext,
        matching predicate: (TokenEntry) -> Bool) -> [OverviewPositionGroupData] {
        let idle = projectedTokens(projected, for: tab, context: context) { entry in
            isVisible(entry, context: context) && predicate(entry)
        }

        return groups(from: idle, context: context)
    }

    /// Borrowed, dashboard-visible tokens grouped by the position that owes them.
    private static func borrowingGroups(
        _ projected: OverviewPositionInputs,
        context: OverviewPositionContext) -> [OverviewPositionGroupData] {
        let borrowed = projectedTokens(projected, for: .borrowing, context: context) { entry in
            isVisible(entry, context: context)
        }

        return groups(from: borrowed, context: context)
    }

    /// Prices each surviving token once and groups them by owning position, preserving
    /// first-appearance order.
    private static func groups(
        from projected: [ProjectedToken],
        context: OverviewPositionContext) -> [OverviewPositionGroupData] {
        var order: [UUID] = []
        var grouped: [UUID: (position: OverviewPositionMeta, tokens: [OverviewPositionTokenData])] = [:]

        for item in projected {
            let token = OverviewPositionTokenData(
                id: item.id,
                entry: item.entry,
                price: price(item.entry, context: context),
                value: tokenValue(item.entry, context: context),
                change24h: change24h(item.entry, context: context))

            if grouped[item.position.id] == nil {
                order.append(item.position.id)
                grouped[item.position.id] = (item.position, [])
            }
            grouped[item.position.id]?.tokens.append(token)
        }

        return order.compactMap { id in
            guard let group = grouped[id] else { return nil }
            return OverviewPositionGroupData(position: group.position, tokens: group.tokens)
        }
    }

    // MARK: - Visibility and pricing

    /// Whether the token passes the dashboard's value and dust thresholds.
    private static func isVisible(_ entry: TokenEntry, context: OverviewPositionContext) -> Bool {
        OverviewPositionVisibility.isVisible(
            token: entry,
            prices: context.prices,
            overrideMap: context.overrideMap,
            settings: context.dashboardSettings,
            usdToDisplayRate: context.fallbackUSDToDisplayRate)
    }

    /// The visibility rule used when ranking 24h changes. Same thresholds as
    /// `isVisible`, but measured against the change reference value rather than the
    /// display value, so a token's eligibility for the movers list is judged by the
    /// value its 24h change was derived from.
    private static func isChangeVisible(_ entry: TokenEntry, context: OverviewPositionContext) -> Bool {
        OverviewPriceChangeFeature.isDashboardEligibleForChange(
            token: entry,
            prices: context.prices,
            changes24h: context.changes24h,
            override: context.overrideMap[entry.assetId],
            settings: context.dashboardSettings,
            usdToDisplayRate: context.fallbackUSDToDisplayRate)
    }

    /// Display-currency price, manual override applied.
    private static func price(_ entry: TokenEntry, context: OverviewPositionContext) -> Decimal {
        OverviewPositionPricing.price(
            token: entry,
            prices: context.prices,
            override: context.overrideMap[entry.assetId],
            fallbackUSDToDisplayRate: context.fallbackUSDToDisplayRate)
    }

    /// Falls back to the 24h change reference so a token with no live price still shows
    /// the value its change was derived from.
    private static func tokenValue(_ entry: TokenEntry, context: OverviewPositionContext) -> Decimal {
        let resolvedValue = OverviewPositionPricing.tokenValue(
            token: entry,
            prices: context.prices,
            override: context.overrideMap[entry.assetId],
            fallbackUSDToDisplayRate: context.fallbackUSDToDisplayRate)
        if resolvedValue != 0 {
            return resolvedValue
        }
        return OverviewPositionPricing.changeReferenceValue(
            token: entry,
            prices: context.prices,
            changes24h: context.changes24h,
            override: context.overrideMap[entry.assetId],
            fallbackUSDToDisplayRate: context.fallbackUSDToDisplayRate)
    }

    /// Display-currency 24h change, manual override applied.
    private static func change24h(_ entry: TokenEntry, context: OverviewPositionContext) -> Decimal {
        OverviewPositionPricing.change24h(
            token: entry,
            prices: context.prices,
            changes24h: context.changes24h,
            override: context.overrideMap[entry.assetId],
            fallbackUSDToDisplayRate: context.fallbackUSDToDisplayRate)
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
}

/// A `PositionToken` projected to value types, tagged with its owning position.
private struct ProjectedToken {
    let id: UUID
    let entry: TokenEntry
    let position: OverviewPositionMeta
}
