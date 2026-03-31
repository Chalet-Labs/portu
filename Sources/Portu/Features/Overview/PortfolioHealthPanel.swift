import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct PortfolioHealthPanel: View {
    let store: StoreOf<AppFeature>
    @Query private var allTokens: [PositionToken]

    private var tokenEntries: [TokenEntry] {
        allTokens.compactMap { token in
            guard let asset = token.asset, token.position?.account?.isActive == true else { return nil }
            return TokenEntry(
                assetId: asset.id, symbol: asset.symbol, name: asset.name,
                category: asset.category, coinGeckoId: asset.coinGeckoId,
                role: token.role, amount: token.amount, usdValue: token.usdValue,
            )
        }
    }

    private var weights: [AssetWeight] {
        PortfolioHealthFeature.computeAssetWeights(tokens: tokenEntries, prices: store.prices)
    }

    private var metrics: DiversificationMetrics {
        let chainCount = Set(allTokens.compactMap { $0.position?.chain }).count
        return PortfolioHealthFeature.computeDiversificationMetrics(
            tokens: tokenEntries, weights: weights, chainCount: chainCount,
        )
    }

    private var riskLevel: RiskLevel {
        PortfolioHealthFeature.classifyRiskLevel(metrics: metrics)
    }

    private var risks: [ConcentrationRisk] {
        PortfolioHealthFeature.computeConcentrationRisks(weights: weights, threshold: Decimal(string: "0.25")!)
    }

    private var displayedWeights: [AssetWeight] {
        store.portfolioHealth.showAllAssets ? weights : Array(weights.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Portfolio Health")
                    .font(.headline)
                Spacer()
                riskBadge
            }

            metricsRow

            if !risks.isEmpty {
                concentrationWarnings
            }

            weightsList

            if weights.count > 5 {
                Button(store.portfolioHealth.showAllAssets ? "Show Top 5" : "Show All") {
                    store.send(.portfolioHealth(.showAllAssetsToggled))
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var riskBadge: some View {
        Text(riskLevel.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(riskLevel.color.opacity(0.15))
            .foregroundStyle(riskLevel.color)
            .clipShape(Capsule())
    }

    private var metricsRow: some View {
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
            Text(value).fontWeight(.medium)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private var concentrationWarnings: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(risks) { risk in
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    Text("\(risk.symbol) is \(risk.percentage.formatted(.percent.precision(.fractionLength(0)))) of portfolio")
                        .font(.caption)
                }
            }
        }
    }

    private var weightsList: some View {
        VStack(spacing: 4) {
            ForEach(displayedWeights) { weight in
                HStack {
                    Text(weight.symbol)
                        .font(.caption.weight(.medium))
                        .frame(width: 50, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: max(4, geo.size.width * CGFloat(truncating: weight.percentage as NSDecimalNumber)))
                    }
                    .frame(height: 8)
                    Text(weight.percentage.formatted(.percent.precision(.fractionLength(1))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
