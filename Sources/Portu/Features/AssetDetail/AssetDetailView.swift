import SwiftUI
import SwiftData
import PortuCore

struct AssetDetailView: View {
    let assetId: UUID

    @Query private var assets: [Asset]
    @Environment(AppState.self) private var appState

    private var asset: Asset? {
        assets.first { $0.id == assetId }
    }

    var body: some View {
        if let asset {
            HSplitView {
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Breadcrumb
                        HStack {
                            Button("← Assets") {
                                appState.selectedSection = .allAssets
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            Text(">")
                                .foregroundStyle(.tertiary)
                            Text(asset.symbol)
                                .fontWeight(.medium)
                        }
                        .font(.caption)

                        // Header
                        HStack(alignment: .firstTextBaseline) {
                            Text(asset.name)
                                .font(.title.weight(.semibold))
                            Text(asset.symbol)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let cgId = asset.coinGeckoId, let price = appState.prices[cgId] {
                                VStack(alignment: .trailing) {
                                    Text(price, format: .currency(code: "USD"))
                                        .font(.title2.weight(.semibold))
                                    if let change = appState.priceChanges24h[cgId] {
                                        HStack(spacing: 4) {
                                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            Text(change, format: .percent.precision(.fractionLength(2)))
                                        }
                                        .foregroundStyle(change >= 0 ? .green : .red)
                                    }
                                }
                            }
                        }

                        AssetPriceChart(assetId: assetId, coinGeckoId: asset.coinGeckoId)
                        AssetHoldingsSummary(assetId: assetId)
                        AssetPositionsTable(assetId: assetId)
                    }
                    .padding()
                }
                .frame(minWidth: 500)
                .layoutPriority(3)

                // Right sidebar
                AssetMetadataSidebar(asset: asset)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                    .layoutPriority(1)
            }
        } else {
            ContentUnavailableView("Asset Not Found", systemImage: "questionmark.circle")
        }
    }
}
