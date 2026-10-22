import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftUI

/// Portfolio Health from the portfolio read model (#124).
struct PortfolioHealthPanel: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        let overview = store.portfolio.overview

        VStack(alignment: .leading, spacing: 12) {
            if let health = overview.health, let currencyCode = overview.currencyCode {
                content(health, currencyCode: currencyCode)
            } else {
                Text("Portfolio Health")
                    .font(DashboardStyle.sectionTitleFont)
                    .foregroundStyle(PortuTheme.dashboardText)
                Text(OverviewPriceDisplay.unvaluedPlaceholder)
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .help(OverviewPriceDisplay.unavailableHelp(buildError: store.portfolio.buildError))
            }
        }
    }

    @ViewBuilder
    private func content(_ health: PortfolioHealthData, currencyCode: String) -> some View {
        let riskLevel = PortfolioHealthFeature.classifyRiskLevel(metrics: health.metrics)
        let risks = health.concentrationRisks
        let weightList = health.weightList(showAll: store.portfolioHealth.showAllAssets)

        HStack {
            Text("Portfolio Health")
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)
            Spacer()
            riskBadge(riskLevel)
        }

        metricsRow(health.metrics)

        if !risks.isEmpty {
            concentrationWarnings(risks)
        }

        weightsList(weightList, currencyCode: currencyCode)

        if health.weights.count > PortfolioHealthWeightList.previewCount {
            Button(store.portfolioHealth.showAllAssets ? "Show Top 5" : "Show All") {
                store.send(.portfolioHealth(.showAllAssetsToggled))
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardGold)
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

    private func weightsList(_ list: PortfolioHealthWeightList, currencyCode: String) -> some View {
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

// #Preview needs a store holding a revaluation — use Xcode's preview canvas with the running app instead
