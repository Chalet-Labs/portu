import SwiftUI
import PortuUI

struct AssetMetadataSidebar: View {
    let assetName: String
    let symbol: String
    let categoryTitle: String
    let coinGeckoID: String?
    let selectedModeTitle: String
    let selectedSummaryLabel: String
    let containsPartialHistory: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    "Asset Metadata",
                    subtitle: "Reference data and chart context for this drill-down"
                )

                StatCard(
                    title: "Name",
                    value: assetName
                )

                StatCard(
                    title: "Symbol",
                    value: symbol
                )

                StatCard(
                    title: "Category",
                    value: categoryTitle
                )

                if let coinGeckoID {
                    StatCard(
                        title: "Price Source",
                        value: "CoinGecko",
                        subtitle: coinGeckoID
                    )
                }

                StatCard(
                    title: "Selected Chart",
                    value: selectedModeTitle,
                    subtitle: selectedSummaryLabel
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("Explorer links are attached to individual positions.", systemImage: "arrow.triangle.branch")
                    Text("A cross-chain asset can appear on multiple networks, so explorer context is derived from each position instead of the asset record.")

                    if containsPartialHistory {
                        Divider()
                        Label("Some historical batches are partial because at least one account was stale during sync.", systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding()
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 340, maxHeight: .infinity, alignment: .topLeading)
    }
}
