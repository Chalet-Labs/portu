import Foundation
import PortuCore

enum OverviewPositionTab: String, CaseIterable {
    case keyChanges = "Key Changes"
    case idleStables = "Idle Stables"
    case idleMajors = "Idle BTC / ETH / SOL"
    case borrowing = "Borrowing"
    case futures = "Futures"
    case options = "Options"

    /// Shown when the tab resolves to no positions.
    var emptyMessage: String {
        switch self {
        case .keyChanges: "No key changes"
        case .idleStables: "No idle stables"
        case .idleMajors: "No idle BTC / ETH / SOL"
        case .borrowing: "No borrowing"
        case .futures, .options: "No deployed positions"
        }
    }

    /// Tabs with no data source yet; they never touch the model graph.
    var isPlaceholder: Bool {
        switch self {
        case .futures, .options: true
        case .keyChanges, .idleStables, .idleMajors, .borrowing: false
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
        switch tab {
        case .keyChanges:
            keyChangeGroups(positions: positions, context: context)
        case .idleStables:
            idleGroups(positions: positions, context: context) { entry in
                entry.portfolioCategory.semanticRole == .stablecoin
            }
        case .idleMajors:
            idleGroups(positions: positions, context: context) { entry in
                PortfolioCategoryDefaults.majorCategoryIDs.contains(entry.portfolioCategory.id)
            }
        case .borrowing:
            borrowingGroups(positions: positions, context: context)
        case .futures, .options:
            []
        }
    }

    // MARK: - Model boundary

    /// The only place position models are read.
    ///
    /// Work is discarded as early as possible: positions are rejected on their own
    /// attributes before any token is projected, tokens are filtered before the
    /// position's metadata is faulted, and each surviving token is projected once.
    private static func projectedTokens(
        positions: [Position],
        context: OverviewPositionContext,
        wherePosition isPositionIncluded: (PositionType) -> Bool = { _ in true },
        including isIncluded: (TokenEntry) -> Bool) -> [ProjectedToken] {
        positions.flatMap { position -> [ProjectedToken] in
            let positionType = position.positionType
            guard isPositionIncluded(positionType) else { return [] }

            let included = position.tokens.compactMap { token -> (id: UUID, entry: TokenEntry)? in
                guard
                    let entry = tokenEntry(for: token, context: context),
                    isIncluded(entry)
                else { return nil }
                return (token.id, entry)
            }
            guard !included.isEmpty else { return [] }

            let meta = OverviewPositionMeta(
                id: position.id,
                title: position.protocolName ?? position.account?.name ?? "Wallet",
                positionType: positionType,
                chain: position.chain)

            return included.map { ProjectedToken(id: $0.id, entry: $0.entry, position: meta) }
        }
    }

    /// Tokens without an asset cannot be priced or categorised, so they are dropped
    /// here exactly as the visibility filters used to drop them.
    private static func tokenEntry(
        for token: PositionToken,
        context: OverviewPositionContext) -> TokenEntry? {
        guard let asset = token.asset else { return nil }
        let identity = OnchainTokenIdentity(chain: asset.upsertChain, contractAddress: asset.upsertContract)
        let coinGeckoId = OverviewWatchlistStore.normalizedID(asset.coinGeckoId)
            ?? TokenIdentityMappingFeature.mappedCoinGeckoID(
                for: identity,
                mappingsByIdentity: context.mappingMap)
        return TokenEntry(
            assetId: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            category: asset.category,
            portfolioCategory: context.categoryResolver.resolve(symbol: asset.symbol, legacyCategory: asset.category),
            coinGeckoId: coinGeckoId,
            onchainIdentity: identity,
            role: token.role,
            amount: token.amount,
            usdValue: token.usdValue,
            logoURL: asset.logoURL)
    }

    // MARK: - Tabs

    /// The biggest movers: change-visible positive tokens ranked by absolute 24h
    /// change, capped at `keyChangeLimit` and grouped by position.
    private static func keyChangeGroups(
        positions: [Position],
        context: OverviewPositionContext) -> [OverviewPositionGroupData] {
        // Ranking needs each candidate's change, so it is computed here and again for
        // the surviving `keyChangeLimit` tokens when their row data is built.
        let ranked = projectedTokens(positions: positions, context: context) { entry in
            entry.role.isPositive && isChangeVisible(entry, context: context)
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
        positions: [Position],
        context: OverviewPositionContext,
        matching predicate: (TokenEntry) -> Bool) -> [OverviewPositionGroupData] {
        let idle = projectedTokens(
            positions: positions,
            context: context,
            wherePosition: { $0 == .idle },
            including: { entry in
                entry.role.isPositive
                    && isVisible(entry, context: context)
                    && predicate(entry)
            })

        return groups(from: idle, context: context)
    }

    /// Borrowed, dashboard-visible tokens grouped by the position that owes them.
    private static func borrowingGroups(
        positions: [Position],
        context: OverviewPositionContext) -> [OverviewPositionGroupData] {
        let borrowed = projectedTokens(positions: positions, context: context) { entry in
            entry.role.isBorrow && isVisible(entry, context: context)
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

/// A `PositionToken` projected to value types, tagged with its owning position.
private struct ProjectedToken {
    let id: UUID
    let entry: TokenEntry
    let position: OverviewPositionMeta
}
