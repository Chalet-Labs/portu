import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AssetDetailView: View {
    let assetId: UUID
    let store: StoreOf<AppFeature>

    @Environment(\.dismiss) private var dismiss
    @Query private var assets: [Asset]

    private var asset: Asset? {
        assets.first { $0.id == assetId }
    }

    var body: some View {
        if let asset {
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                        DashboardPageHeader(asset.name, subtitle: asset.symbol) {
                            Button {
                                dismiss()
                                store.send(.sectionSelected(.allAssets))
                            } label: {
                                Label("Assets", systemImage: "chevron.left")
                            }
                            .dashboardControl()
                        }

                        if
                            let info = AssetDetailFeature.headerPriceInfo(
                                coinGeckoId: asset.coinGeckoId,
                                prices: store.prices,
                                changes24h: store.priceChanges24h) {
                            DashboardCard {
                                HStack(alignment: .firstTextBaseline) {
                                    DashboardMetricBlock(
                                        title: "Price",
                                        value: info.price.formatted(.currency(code: "USD")))
                                    Spacer()
                                    if let change = info.change24h {
                                        HStack(spacing: 4) {
                                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            Text(change, format: .percent.precision(.fractionLength(2)))
                                        }
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(change >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                                    }
                                }
                            }
                        }

                        AssetPriceChart(assetId: assetId, coinGeckoId: asset.coinGeckoId, store: store)
                            .dashboardCard()
                        AssetHoldingsSummary(assetId: assetId, store: store)
                            .dashboardCard()
                        AssetPositionsTable(assetId: assetId, store: store)
                            .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
                    }
                    .padding(DashboardStyle.pagePadding)
                }
                .frame(minWidth: 500)
                .layoutPriority(3)
                .background(PortuTheme.dashboardBackground)

                AssetMetadataSidebar(asset: asset)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
                    .layoutPriority(1)
            }
            .dashboardPage()
        } else {
            ContentUnavailableView("Asset Not Found", systemImage: "questionmark.circle")
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
        }
    }
}
