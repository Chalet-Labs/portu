import Foundation
import PortuCore

/// The prices an Overview seam values with.
///
/// The USD half (`livePricesUSD`, `liveChanges24h`, `historical`) is what the seams read once they
/// value through `PortfolioValuation`. The display-currency books are transitional: today's
/// pricing functions still take them, and they go when the seams move to the module.
struct OverviewPriceInputs: Equatable {
    var livePricesUSD: [String: Decimal] = [:]
    /// Live 24h fractions keyed by price ID; also today's live half of the merged changes.
    var liveChanges24h: [String: Decimal] = [:]
    var historical: HistoricalMarketPrices = .empty
    var liveDisplayPrices: [String: Decimal] = [:]
    var historicalDisplayPrices: [String: Decimal] = [:]
    var historicalChanges24h: [String: Decimal] = [:]

    var market: MarketPrices {
        MarketPrices(liveUSD: livePricesUSD, liveChanges24h: liveChanges24h, historical: historical)
    }

    var displayPrices: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedPrices(live: liveDisplayPrices, historical: historicalDisplayPrices)
    }

    var displayChanges24h: [String: Decimal] {
        OverviewHistoricalPriceChangeFeature.mergedChanges24h(live: liveChanges24h, historical: historicalChanges24h)
    }
}

/// Everything an Overview seam values: the active-account inputs and the pricing context, gathered
/// once per render pass.
struct OverviewValuationContext {
    let inputs: [ValuationInput]
    let overrides: [TokenPricingOverrideSnapshot]
    let mappings: [TokenIdentityMappingSnapshot]
    let settings: TokenDashboardSettings
    let usdToDisplayRate: Decimal
    let prices: OverviewPriceInputs

    var tokens: [TokenEntry] {
        inputs.map(\.token)
    }
}

// MARK: - Headline (Overview top bar, Sidebar header)

struct OverviewHeadline: Equatable {
    let total: Decimal
    let change24h: Decimal
    /// `change / (total − change)`; `nil` shows "—".
    let changePercentage: Decimal?
}

extension OverviewFeature {
    /// The headline total and its 24h change. The top bar and the Sidebar header both show this.
    static func headline(_ context: OverviewValuationContext) -> OverviewHeadline {
        let tokens = context.tokens
        let prices = context.prices.displayPrices
        let total = portfolioTotalValue(
            tokens: tokens,
            prices: prices,
            overrides: context.overrides,
            mappings: context.mappings,
            settings: context.settings,
            fallbackUSDToDisplayRate: context.usdToDisplayRate)
        let change = OverviewPriceChangeFeature.portfolioChange24h(
            tokens: tokens,
            prices: prices,
            changes24h: context.prices.displayChanges24h,
            overrides: context.overrides,
            mappings: context.mappings,
            settings: context.settings,
            fallbackUSDToDisplayRate: context.usdToDisplayRate)
        let prior = total - change
        return OverviewHeadline(
            total: total,
            change24h: change,
            changePercentage: prior != 0 ? change / prior : 0)
    }
}

// MARK: - Top Assets donut

struct OverviewTopAssets: Equatable {
    let slices: [OverviewAssetSlice]
    /// The hidden-balances line, in the display currency; `nil` while the donut drops hidden rows.
    let hidden: HiddenBalances?
    /// The hidden line's share, rounded together with the slices so all of them sum to 100 (F4).
    let hiddenDisplayPercent: Int?
}

extension OverviewFeature {
    static func topAssets(_ mode: TopAssetMode, context: OverviewValuationContext) -> OverviewTopAssets {
        let tokens = dashboardTokens(context)
        let prices = context.prices.displayPrices
        let slices = switch mode {
        case .assets:
            topAssetSlices(
                from: tokens,
                prices: prices,
                overrides: context.overrides,
                limit: 5,
                fallbackUSDToDisplayRate: context.usdToDisplayRate)
        case .category:
            categorySlices(
                from: tokens,
                prices: prices,
                overrides: context.overrides,
                limit: 6,
                fallbackUSDToDisplayRate: context.usdToDisplayRate)
        }
        return OverviewTopAssets(slices: slices, hidden: nil, hiddenDisplayPercent: nil)
    }

    // MARK: - Watchlist

    /// Held rows first, then watched coins that are not held.
    static func watchlistRows(
        _ context: OverviewValuationContext,
        assetsByCoinGeckoId: [String: OverviewAssetCandidate],
        watchlistIDs: [String]) -> [OverviewPriceRowData] {
        priceRows(
            tokens: dashboardTokens(context),
            assetsByCoinGeckoId: assetsByCoinGeckoId,
            prices: context.prices.displayPrices,
            changes24h: context.prices.displayChanges24h,
            watchlistIDs: watchlistIDs,
            overrides: context.overrides,
            fallbackUSDToDisplayRate: context.usdToDisplayRate)
    }

    // MARK: - Polling candidates

    /// The live-polling set: the top holdings by value, then the watchlist.
    static func pricePollingIDs(
        _ context: OverviewValuationContext,
        watchlistIDs: [String],
        portfolioLimit: Int = 25) -> [String] {
        pricePollingIDs(
            tokens: TokenSettingsFeature.applyIdentityMappings(
                to: context.tokens,
                mappings: context.mappings,
                overrides: context.overrides),
            prices: context.prices.displayPrices,
            watchlistIDs: watchlistIDs,
            overrides: context.overrides,
            settings: context.settings,
            portfolioLimit: portfolioLimit,
            usdToDisplayRate: context.usdToDisplayRate)
    }

    /// The identity-mapped tokens the dashboard filter shows, as the donut and watchlist use them.
    private static func dashboardTokens(_ context: OverviewValuationContext) -> [TokenEntry] {
        TokenSettingsFeature.dashboardEligibleTokens(
            tokens: TokenSettingsFeature.applyIdentityMappings(
                to: context.tokens,
                mappings: context.mappings,
                overrides: context.overrides),
            prices: context.prices.displayPrices,
            overrides: context.overrides,
            settings: context.settings,
            usdToDisplayRate: context.usdToDisplayRate)
    }
}

// MARK: - Summary cards

struct OverviewSummaryCardRow: Equatable, Identifiable {
    let label: String
    let value: Decimal

    var id: String {
        label
    }
}

struct OverviewSummaryCard: Equatable, Identifiable {
    let title: String
    let rows: [OverviewSummaryCardRow]

    var id: String {
        title
    }
}

extension OverviewSummaryCardsFeature {
    /// The summary cards in display order. Each card's rows are fixed and never display-filtered.
    static func cards(
        _ context: OverviewValuationContext,
        categories: [PortfolioCategorySnapshot]) -> [OverviewSummaryCard] {
        let tokens = context.inputs.map {
            OverviewSummaryToken(token: $0.token, positionType: $0.position.positionType)
        }
        let prices = context.prices.displayPrices
        let idle = idleBreakdown(
            tokens: tokens,
            prices: prices,
            overrides: context.overrides,
            settings: context.settings,
            categories: categories,
            fallbackUSDToDisplayRate: context.usdToDisplayRate)
        let deployed = deployedBreakdown(
            tokens: tokens,
            prices: prices,
            overrides: context.overrides,
            settings: context.settings,
            fallbackUSDToDisplayRate: context.usdToDisplayRate)
        return [
            OverviewSummaryCard(title: "Idle", rows: idle.map { OverviewSummaryCardRow(label: $0.0, value: $0.1) }),
            OverviewSummaryCard(title: "Deployed", rows: deployed.map { OverviewSummaryCardRow(label: $0.0, value: $0.1) })
        ]
    }
}

// MARK: - Portfolio health

struct PortfolioHealthData: Equatable {
    let weights: [AssetWeight]
    let metrics: DiversificationMetrics
    /// The expanded list's hidden-balances line, in the display currency; `nil` while hidden rows are dropped.
    let hidden: HiddenBalances?
    /// The hidden line's share of the weight list, rounded together with the weights (F4).
    let hiddenShare: Decimal?
}

extension PortfolioHealthFeature {
    /// Weights and metrics. `legacyChainCount` is the panel's chain count over every stored token,
    /// which the active-account inputs cannot reproduce.
    static func health(_ context: OverviewValuationContext, legacyChainCount: Int) -> PortfolioHealthData {
        let prices = context.prices.displayPrices
        let tokens = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: context.tokens,
            prices: prices,
            overrides: context.overrides,
            settings: context.settings,
            usdToDisplayRate: context.usdToDisplayRate)
        let weights = computeAssetWeights(
            tokens: tokens,
            prices: prices,
            fallbackUSDToDisplayRate: context.usdToDisplayRate)
        return PortfolioHealthData(
            weights: weights,
            metrics: computeDiversificationMetrics(tokens: tokens, weights: weights, chainCount: legacyChainCount),
            hidden: nil,
            hiddenShare: nil)
    }
}
