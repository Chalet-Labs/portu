import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AssetHoldingsSummary: View {
    let assetId: UUID
    let store: StoreOf<AppFeature>

    @Query private var allTokens: [PositionToken]

    private var summary: HoldingsSummary {
        let entries = PositionTokenEntry.fromActiveTokens(allTokens, assetId: assetId)
        return AssetDetailFeature.computeHoldingsSummary(tokens: entries, prices: store.prices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Holdings Summary")
                .font(DashboardStyle.sectionTitleFont)
                .foregroundStyle(PortuTheme.dashboardText)

            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Accounts").font(.caption).foregroundStyle(PortuTheme.dashboardSecondaryText)
                    Text("\(summary.accountCount)")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }
                VStack(alignment: .leading) {
                    Text("Total Amount").font(.caption).foregroundStyle(PortuTheme.dashboardSecondaryText)
                    Text(summary.totalAmount, format: .number.precision(.fractionLength(2 ... 8)))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }
                VStack(alignment: .leading) {
                    Text("Total Value").font(.caption).foregroundStyle(PortuTheme.dashboardSecondaryText)
                    Text(summary.totalValue, format: .currency(code: "USD"))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }
            }

            if !summary.byChain.isEmpty {
                Text("On Networks").font(.subheadline.weight(.medium))
                    .foregroundStyle(PortuTheme.dashboardText)
                ForEach(summary.byChain) { chain in
                    HStack {
                        Text(chain.name)
                        Spacer()
                        Text(chain.share, format: .percent.precision(.fractionLength(1)))
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                        Text(chain.value, format: .currency(code: "USD"))
                            .font(DashboardStyle.monoTableFont)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                }
            }
        }
    }
}
