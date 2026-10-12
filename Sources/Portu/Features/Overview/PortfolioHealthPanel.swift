import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PortfolioHealthPanel: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState
    @Query private var allTokens: [PositionToken]
    var sources = OverviewValuationSources()
    var categories = OverviewCategorySource()

    private var health: PortfolioHealthData {
        sources.health(
            allTokens,
            categoryResolver: categories.resolver)
    }

    var body: some View {
        let currentHealth = health
        let riskLevel = PortfolioHealthFeature.classifyRiskLevel(metrics: currentHealth.metrics)
        let risks = currentHealth.concentrationRisks
        let weightList = currentHealth.weightList(showAll: store.portfolioHealth.showAllAssets)

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

            weightsList(weightList)

            if currentHealth.weights.count > PortfolioHealthWeightList.previewCount {
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

    private func weightsList(_ list: PortfolioHealthWeightList) -> some View {
        VStack(spacing: 4) {
            ForEach(list.rows) { row in
                HStack {
                    Text(row.weight.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PortuTheme.dashboardText)
                        .frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PortuTheme.dashboardGoldMuted)
                            .frame(width: max(4, geo.size.width * CGFloat(truncating: row.weight.percentage as NSDecimalNumber)))
                    }
                    .frame(height: 8)
                    shareText(row.share)
                }
            }

            if let hidden = list.hidden {
                HStack {
                    Text(OverviewPriceDisplay.hiddenBalancesLine(hidden, basis: .positiveNet, currencyCode: currencyCode))
                        .font(.caption2)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    shareText(list.hiddenShare)
                }
            }
        }
    }

    private func shareText(_ share: Decimal?) -> some View {
        Text(share.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
            .font(.caption2)
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
            .frame(width: 40, alignment: .trailing)
    }

    /// `AppState`'s currency, like the rate the hidden line is converted at, so the two always match.
    private var currencyCode: String {
        appState.selectedCurrency.displayCode
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
