import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct OverviewSummaryCards: View {
    @Environment(AppState.self) private var appState
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices
    @Environment(\.historicalMarketPrices) private var historicalMarketPrices
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

    private var overrideSnapshots: [TokenPricingOverrideSnapshot] {
        tokenPricingOverrides.map(TokenPricingOverrideSnapshot.init)
    }

    private var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: Decimal(minimumDashboardValue),
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }

    private var cards: [OverviewSummaryCard] {
        let resolver = categoryResolver
        return OverviewSummaryCardsFeature.cards(
            OverviewValuationContext(
                inputs: ValuationInput.activeAccounts(positions.flatMap(\.tokens), categoryResolver: resolver),
                overrides: overrideSnapshots,
                mappings: [],
                settings: dashboardSettings,
                usdToDisplayRate: appState.currentUSDToDisplayRate,
                prices: OverviewPriceInputs(
                    livePricesUSD: appState.livePricesUSD,
                    historical: historicalMarketPrices,
                    liveDisplayPrices: appState.prices,
                    historicalDisplayPrices: historicalDisplayPrices)),
            categories: resolver.categories)
    }

    private var currencyCode: String {
        appState.selectedCurrency.displayCode
    }

    var body: some View {
        HStack(alignment: .top, spacing: PortuTheme.dashboardContentSpacing) {
            ForEach(cards) { card in
                summaryCard(title: card.title, items: card.rows)
            }
        }
    }

    private func summaryCard(title: String, items: [OverviewSummaryCardRow]) -> some View {
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
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(OverviewPriceDisplay.currency(item.value, currencyCode: currencyCode))
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
    static func emptyState(for _: String) -> String {
        "No deployed positions"
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
        categories: [PortfolioCategorySnapshot],
        fallbackUSDToDisplayRate: Decimal = 1) -> [(String, Decimal)] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var stablesFiat: Decimal = 0
        var majors: Decimal = 0
        var otherTokens: Decimal = 0

        for summaryToken in tokens where summaryToken.positionType == .idle {
            guard
                let token = visibleToken(
                    summaryToken.token,
                    prices: prices,
                    overrideMap: overrideMap,
                    settings: settings,
                    fallbackUSDToDisplayRate: fallbackUSDToDisplayRate) else {
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
        settings: TokenDashboardSettings = .defaults,
        fallbackUSDToDisplayRate: Decimal = 1) -> [(String, Decimal)] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var lending: Decimal = 0
        var staked: Decimal = 0
        var yield: Decimal = 0

        for summaryToken in tokens {
            guard
                let token = visibleToken(
                    summaryToken.token,
                    prices: prices,
                    overrideMap: overrideMap,
                    settings: settings,
                    fallbackUSDToDisplayRate: fallbackUSDToDisplayRate) else {
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
        settings: TokenDashboardSettings,
        fallbackUSDToDisplayRate: Decimal) -> TokenEntry? {
        let override = overrideMap[token.assetId]
        guard token.role.isPositive else { return nil }
        guard override?.isIgnored != true else { return nil }

        let value = OverviewPositionPricing.tokenValue(
            token: token,
            prices: prices,
            override: override,
            fallbackUSDToDisplayRate: fallbackUSDToDisplayRate)
        if value == 0 {
            guard override?.alwaysShow == true || !settings.hideUnpriced else { return nil }
        } else if abs(value) < normalizedThreshold(settings.minimumDashboardValue) * fallbackUSDToDisplayRate {
            guard override?.alwaysShow == true || !settings.hideDust else { return nil }
        }

        let adjusted = TokenSettingsFeature.dashboardAdjustedToken(from: token, override: override)
        return TokenEntry(
            assetId: adjusted.assetId,
            symbol: adjusted.symbol,
            name: adjusted.name,
            category: adjusted.category,
            portfolioCategory: adjusted.portfolioCategory,
            coinGeckoId: adjusted.coinGeckoId,
            onchainIdentity: adjusted.onchainIdentity,
            role: adjusted.role,
            amount: adjusted.amount,
            usdValue: value,
            logoURL: adjusted.logoURL,
            syncedAt: adjusted.syncedAt)
    }
}

private func normalizedThreshold(_ value: Decimal) -> Decimal {
    value < 0 ? 0 : value
}
