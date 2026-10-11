import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PortfolioHealthPanel: View {
    let store: StoreOf<AppFeature>
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices
    @Environment(\.historicalMarketPrices) private var historicalMarketPrices
    @Query private var allTokens: [PositionToken]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]
    @Query private var tokenPricingOverrides: [TokenPricingOverride]
    @AppStorage(TokenDashboardSettings.minimumDashboardValueKey)
    private var minimumDashboardValue = NSDecimalNumber(decimal: TokenDashboardSettings.defaultMinimumDashboardValue).doubleValue
    @AppStorage(TokenDashboardSettings.hideUnpricedKey)
    private var hideUnpriced = true
    @AppStorage(TokenDashboardSettings.hideDustKey)
    private var hideDust = true

    private var health: PortfolioHealthData {
        PortfolioHealthFeature.health(
            OverviewValuationContext(
                inputs: ValuationInput.activeAccounts(
                    allTokens,
                    categoryResolver: PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules)),
                overrides: overrideSnapshots,
                mappings: [],
                settings: dashboardSettings,
                usdToDisplayRate: store.currentUSDToDisplayRate,
                prices: OverviewPriceInputs(
                    livePricesUSD: store.livePricesUSD,
                    historical: historicalMarketPrices,
                    liveDisplayPrices: store.liveDisplayPrices,
                    historicalDisplayPrices: historicalDisplayPrices)),
            legacyChainCount: Set(allTokens.compactMap { $0.position?.chain }).count)
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

    var body: some View {
        let currentHealth = health
        let riskLevel = PortfolioHealthFeature.classifyRiskLevel(metrics: currentHealth.metrics)
        let risks = PortfolioHealthFeature.computeConcentrationRisks(
            weights: currentHealth.weights,
            threshold: Decimal(string: "0.25")!)
        let displayedWeights = store.portfolioHealth.showAllAssets ? currentHealth.weights : Array(currentHealth.weights.prefix(5))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Portfolio Health")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                Spacer()
                riskBadge(riskLevel)
            }

            metricsRow(currentHealth.metrics)

            if !risks.isEmpty {
                concentrationWarnings(risks)
            }

            weightsList(displayedWeights)

            if currentHealth.weights.count > 5 {
                Button(store.portfolioHealth.showAllAssets ? "Show Top 5" : "Show All") {
                    store.send(.portfolioHealth(.showAllAssetsToggled))
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardGold)
            }
        }
    }

    private func riskBadge(_ riskLevel: RiskLevel) -> some View {
        Text(riskLevel.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(riskLevel.color.opacity(0.15))
            .foregroundStyle(riskLevel.color)
            .clipShape(Capsule())
    }

    private func metricsRow(_ metrics: DiversificationMetrics) -> some View {
        HStack(spacing: 16) {
            metricItem("Assets", "\(metrics.assetCount)")
            metricItem("Chains", "\(metrics.chainCount)")
            metricItem("Stables", metrics.stablecoinRatio.formatted(.percent.precision(.fractionLength(0))))
            metricItem("HHI", metrics.herfindahlIndex.formatted(.number.precision(.fractionLength(2))))
        }
        .font(.caption)
    }

    private func metricItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(PortuTheme.dashboardText)
            Text(label)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
        }
    }

    private func concentrationWarnings(_ risks: [ConcentrationRisk]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(risks) { risk in
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text("\(risk.symbol) is \(risk.percentage.formatted(.percent.precision(.fractionLength(0)))) of portfolio")
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }
            }
        }
    }

    private func weightsList(_ displayedWeights: [AssetWeight]) -> some View {
        VStack(spacing: 4) {
            ForEach(displayedWeights) { weight in
                HStack {
                    Text(weight.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PortuTheme.dashboardText)
                        .frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PortuTheme.dashboardGoldMuted)
                            .frame(width: max(4, geo.size.width * CGFloat(truncating: weight.percentage as NSDecimalNumber)))
                    }
                    .frame(height: 8)
                    Text(weight.percentage.formatted(.percent.precision(.fractionLength(1))))
                        .font(.caption2)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - RiskLevel UI

extension RiskLevel {
    var label: String {
        switch self {
        case .low: "Low Risk"
        case .medium: "Medium Risk"
        case .high: "High Risk"
        }
    }

    var color: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

// #Preview requires a ModelContainer for @Query — use Xcode's preview canvas with the running app instead
