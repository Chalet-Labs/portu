// Sources/Portu/Features/Overview/OverviewSummaryCards.swift
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewSummaryCards: View {
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

    /// Only positions from active accounts
    private var positions: [Position] {
        allPositions.filter { $0.account?.isActive == true }
    }

    private var categoryResolver: PortfolioCategoryResolver {
        PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)
    }

    private var summaryTokens: [OverviewSummaryToken] {
        let resolver = categoryResolver
        return positions.flatMap { position in
            position.tokens.compactMap { token in
                guard let asset = token.asset else { return nil }
                return OverviewSummaryToken(
                    token: TokenEntry(
                        assetId: asset.id,
                        symbol: asset.symbol,
                        name: asset.name,
                        category: asset.category,
                        portfolioCategory: resolver.resolve(symbol: asset.symbol, legacyCategory: asset.category),
                        coinGeckoId: asset.coinGeckoId,
                        role: token.role,
                        amount: token.amount,
                        usdValue: token.usdValue,
                        logoURL: asset.logoURL),
                    positionType: position.positionType)
            }
        }
    }

    private var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init)
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    private var idleBreakdown: [(String, Decimal)] {
        OverviewSummaryCardsFeature.idleBreakdown(
            tokens: summaryTokens,
            prices: appState.prices,
            overrides: overrideSnapshots,
            settings: dashboardSettings,
            categories: categoryResolver.categories)
    }

    private var deployedBreakdown: [(String, Decimal)] {
        OverviewSummaryCardsFeature.deployedBreakdown(
            tokens: summaryTokens,
            prices: appState.prices,
            overrides: overrideSnapshots,
            settings: dashboardSettings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: PortuTheme.dashboardContentSpacing) {
            summaryCard(title: "Idle", items: idleBreakdown)
            summaryCard(title: "Deployed", items: deployedBreakdown)
            summaryCard(title: "Futures", items: []) // Future work
        }
    }

    private func summaryCard(title: String, items: [(String, Decimal)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)
                .lineLimit(1)

            if items.isEmpty {
                Text(OverviewSummaryCardText.emptyState(for: title))
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ForEach(items, id: \.0) { label, value in
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(OverviewPriceDisplay.currency(value))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(PortuTheme.dashboardText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .dashboardCard()
    }
}

enum OverviewSummaryCardText {
    static func emptyState(for title: String) -> String {
        title == "Futures" ? "Coming soon" : "No deployed positions"
    }
}

struct OverviewSummaryToken: Equatable {
    let token: TokenEntry
    let positionType: PositionType
}

enum OverviewSummaryCardsFeature {
    static func idleBreakdown(
        tokens: [OverviewSummaryToken],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults,
        categories: [PortfolioCategorySnapshot]) -> [(String, Decimal)] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var stablesFiat: Decimal = 0
        var majors: Decimal = 0
        var otherTokens: Decimal = 0

        for summaryToken in tokens where summaryToken.positionType == .idle {
            guard let token = visibleToken(summaryToken.token, prices: prices, overrideMap: overrideMap, settings: settings) else {
                continue
            }

            if token.portfolioCategory.semanticRole == .stablecoin || token.portfolioCategory.semanticRole == .fiat {
                stablesFiat += token.usdValue
            } else if PortfolioCategoryDefaults.majorCategoryIDs.contains(token.portfolioCategory.id) {
                majors += token.usdValue
            } else {
                otherTokens += token.usdValue
            }
        }

        return [
            ("Stablecoins & Fiat", stablesFiat),
            (OverviewSummaryLabels.majorCategoryTitle(categories: categories), majors),
            ("Tokens & Memecoins", otherTokens)
        ]
    }

    static func deployedBreakdown(
        tokens: [OverviewSummaryToken],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults) -> [(String, Decimal)] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var lending: Decimal = 0
        var staked: Decimal = 0
        var yield: Decimal = 0

        for summaryToken in tokens {
            guard let token = visibleToken(summaryToken.token, prices: prices, overrideMap: overrideMap, settings: settings) else {
                continue
            }

            switch summaryToken.positionType {
            case .lending:
                lending += token.usdValue
            case .staking:
                staked += token.usdValue
            case .farming, .liquidityPool:
                yield += token.usdValue
            default:
                break
            }
        }

        return [
            ("Lending", lending),
            ("Staked", staked),
            ("Yield", yield)
        ]
    }

    private static func visibleToken(
        _ token: TokenEntry,
        prices: [String: Decimal],
        overrideMap: [UUID: TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings) -> TokenEntry? {
        let override = overrideMap[token.assetId]
        guard token.role.isPositive else { return nil }
        guard
            TokenSettingsFeature.isDashboardEligible(
                token: token,
                prices: prices,
                override: override,
                settings: settings)
        else {
            return nil
        }
        let adjusted = TokenSettingsFeature.dashboardAdjustedToken(from: token, override: override)
        return TokenEntry(
            assetId: adjusted.assetId,
            symbol: adjusted.symbol,
            name: adjusted.name,
            category: adjusted.category,
            portfolioCategory: adjusted.portfolioCategory,
            coinGeckoId: adjusted.coinGeckoId,
            role: adjusted.role,
            amount: adjusted.amount,
            usdValue: TokenSettingsFeature.resolvedValue(token: token, prices: prices, override: override) ?? adjusted.usdValue,
            logoURL: adjusted.logoURL)
    }
}
