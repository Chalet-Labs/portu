import ComposableArchitecture
import PortuCore
import SwiftData
import SwiftUI

struct AssetDetailView: View {
    let assetId: UUID
    let store: StoreOf<AppFeature>

    @Query private var assets: [Asset]

    private var asset: Asset? {
        assets.first { $0.id == assetId }
    }

    var body: some View {
        if let asset {
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Breadcrumb
                        HStack {
                            Button("← Assets") {
                                store.send(.sectionSelected(.allAssets))
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
                            if
                                let info = AssetDetailFeature.headerPriceInfo(
                                    coinGeckoId: asset.coinGeckoId,
                                    prices: store.prices,
                                    changes24h: store.priceChanges24h) {
                                VStack(alignment: .trailing) {
                                    Text(info.price, format: .currency(code: "USD"))
                                        .font(.title2.weight(.semibold))
                                    if let change = info.change24h {
                                        HStack(spacing: 4) {
                                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            Text(change, format: .percent.precision(.fractionLength(2)))
                                        }
                                        .foregroundStyle(change >= 0 ? .green : .red)
                                    }
                                }
                            }
                        }

                        AssetPriceChart(assetId: assetId, coinGeckoId: asset.coinGeckoId, store: store)
                        AssetHoldingsSummary(assetId: assetId, store: store)
                        AssetPositionsTable(assetId: assetId, store: store)
                    }
                    .padding()
                }
                .frame(minWidth: 500)
                .layoutPriority(3)

                AssetMetadataSidebar(asset: asset)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                    .layoutPriority(1)
            }
        } else {
            ContentUnavailableView("Asset Not Found", systemImage: "questionmark.circle")
        }
    }
}
