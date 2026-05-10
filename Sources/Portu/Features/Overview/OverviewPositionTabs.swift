import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewPositionTabs: View {
    @Environment(AppState.self) private var appState
    @Query private var allPositions: [Position]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @Query(sort: [SortDescriptor(\TokenPricingOverride.updatedAt, order: .reverse)])
    private var tokenPricingOverrides: [TokenPricingOverride]
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    @State private var selectedTab: OverviewTab = .keyChanges

    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    enum OverviewTab: String, CaseIterable {
        case keyChanges = "Key Changes"
        case idleStables = "Idle Stables"
        case idleMajors = "Idle BTC / ETH / SOL"
        case borrowing = "Borrowing"
        case futures = "Futures"
        case options = "Options"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(OverviewTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(height: 1)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 12) {
                switch selectedTab {
                case .keyChanges:
                    positionCards(tokens: keyChangeTokens, emptyTitle: "No key changes")
                case .idleStables:
                    positionCards(tokens: idleStableTokens, emptyTitle: "No idle stables")
                case .idleMajors:
                    positionCards(tokens: idleMajorTokens, emptyTitle: "No idle BTC / ETH / SOL")
                case .borrowing:
                    borrowingView
                case .futures, .options:
                    emptyState("No deployed positions")
                }
            }
            .padding(14)
        }
    }

    private func tabButton(_ tab: OverviewTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedTab == tab ? PortuTheme.dashboardGold : .clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Token filtering

    private var allActiveTokens: [(PositionToken, Position)] {
        positions.flatMap { position in
            position.tokens.map { ($0, position) }
        }
    }

    private var visibleActiveTokens: [(PositionToken, Position)] {
        allActiveTokens.filter { token, _ in
            isDashboardVisible(token)
        }
    }

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private var overrideMap: [UUID: TokenPricingOverrideSnapshot] {
        TokenSettingsFeature.overridesByAssetId(tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init))
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    private var keyChangeTokens: [(PositionToken, Position)] {
        visibleActiveTokens
            .filter(\.0.role.isPositive)
            .compactMap { token, position -> TokenChangeCandidate? in
                let change = tokenChange24h(token)
                guard change != 0 else { return nil }
                return TokenChangeCandidate(token: token, position: position, change: change)
            }
            .sorted {
                let lhs = abs($0.change)
                let rhs = abs($1.change)
                if lhs == rhs {
                    return ($0.token.asset?.symbol ?? "") < ($1.token.asset?.symbol ?? "")
                }
                return lhs > rhs
            }
            .prefix(20)
            .map { ($0.token, $0.position) }
    }

    private var idleStableTokens: [(PositionToken, Position)] {
        let resolver = categoryResolver
        return visibleActiveTokens
            .filter { token, position in
                guard position.positionType == .idle, token.role.isPositive, let asset = token.asset else { return false }
                return resolver
                    .resolve(symbol: asset.symbol, legacyCategory: asset.category)
                    .semanticRole == .stablecoin
            }
    }

    private var idleMajorTokens: [(PositionToken, Position)] {
        let resolver = categoryResolver
        return visibleActiveTokens
            .filter { token, position in
                guard position.positionType == .idle, token.role.isPositive, let asset = token.asset else { return false }
                let category = resolver.resolve(symbol: asset.symbol, legacyCategory: asset.category)
                return PortfolioCategoryDefaults.majorCategoryIDs.contains(category.id)
            }
    }

    private func tokenChange24h(_ token: PositionToken) -> Decimal {
        guard let entry = tokenEntry(for: token) else { return 0 }
        return OverviewPositionPricing.change24h(
            token: entry,
            prices: appState.prices,
            changes24h: appState.priceChanges24h,
            override: overrideMap[entry.assetId])
    }

    // MARK: - Position cards

    private func positionCards(
        tokens: [(PositionToken, Position)],
        emptyTitle: String) -> some View {
        Group {
            if tokens.isEmpty {
                emptyState(emptyTitle)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedTokens(tokens)) { group in
                        OverviewPositionGroupCard(
                            group: group,
                            price: price,
                            tokenValue: tokenValue,
                            tokenChange24h: tokenChange24h)
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardTertiaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }

    private func groupedTokens(_ tokens: [(PositionToken, Position)]) -> [OverviewPositionGroupData] {
        var order: [UUID] = []
        var grouped: [UUID: (position: Position, tokens: [PositionToken])] = [:]

        for (token, position) in tokens {
            if grouped[position.id] == nil {
                order.append(position.id)
                grouped[position.id] = (position, [])
            }
            grouped[position.id]?.tokens.append(token)
        }

        return order.compactMap { id in
            guard let group = grouped[id] else { return nil }
            return OverviewPositionGroupData(
                id: id,
                position: group.position,
                tokens: group.tokens)
        }
    }

    // MARK: - Borrowing

    @ViewBuilder
    private var borrowingView: some View {
        let borrowPositions = positions.compactMap { position -> OverviewPositionGroupData? in
            let tokens = position.tokens.filter { token in
                token.role.isBorrow && isDashboardVisible(token)
            }
            guard !tokens.isEmpty else { return nil }
            return OverviewPositionGroupData(
                id: position.id,
                position: position,
                tokens: tokens)
        }

        if borrowPositions.isEmpty {
            emptyState("No borrowing")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(borrowPositions, id: \.id) { group in
                    OverviewPositionGroupCard(
                        group: group,
                        price: price,
                        tokenValue: tokenValue,
                        tokenChange24h: tokenChange24h)
                }
            }
        }
    }

    // MARK: - Helpers

    private func isDashboardVisible(_ token: PositionToken) -> Bool {
        guard let entry = tokenEntry(for: token) else { return false }
        return OverviewPositionVisibility.isVisible(
            token: entry,
            prices: appState.prices,
            overrideMap: overrideMap,
            settings: dashboardSettings)
    }

    private func tokenEntry(for token: PositionToken) -> TokenEntry? {
        guard let asset = token.asset else { return nil }
        return TokenEntry(
            assetId: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            category: asset.category,
            portfolioCategory: categoryResolver.resolve(symbol: asset.symbol, legacyCategory: asset.category),
            coinGeckoId: asset.coinGeckoId,
            role: token.role,
            amount: token.amount,
            usdValue: token.usdValue,
            logoURL: asset.logoURL)
    }

    private func price(_ token: PositionToken) -> Decimal {
        guard let entry = tokenEntry(for: token) else { return 0 }
        return OverviewPositionPricing.price(
            token: entry,
            prices: appState.prices,
            override: overrideMap[entry.assetId])
    }

    private func tokenValue(_ token: PositionToken) -> Decimal {
        guard let entry = tokenEntry(for: token) else { return 0 }
        return OverviewPositionPricing.tokenValue(
            token: entry,
            prices: appState.prices,
            override: overrideMap[entry.assetId])
    }
}
