import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AssetDetailView: View {
    let assetId: UUID
    let store: StoreOf<AppFeature>

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    var sources = ValuationSources()
    @Query private var assets: [Asset]
    /// Every token in the store: `Asset` has no inverse relationship, and a predicate through
    /// `asset?.id` is the optional chaining AGENTS.md bans, so the projection filters in Swift once.
    @Query private var tokens: [PositionToken]

    init(assetId: UUID, store: StoreOf<AppFeature>) {
        self.assetId = assetId
        self.store = store
        _assets = Query(Self.assetDescriptor(id: assetId))
    }

    /// Fetches only the shown asset instead of every asset in the store.
    static func assetDescriptor(id: UUID) -> FetchDescriptor<Asset> {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// The query already narrows to this id; matching again keeps the view correct if that ever changes.
    private var asset: Asset? {
        assets.first { $0.id == assetId }
    }

    private var currencyCode: String {
        appState.currencyCode
    }

    var body: some View {
        if let asset {
            let projection = AssetDetailProjection(asset, tokens: tokens)
            let page = sources.assetDetail(projection)
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
                        DashboardPageHeader(projection.asset.name, subtitle: projection.asset.symbol) {
                            Button {
                                dismiss()
                                store.send(.sectionSelected(.allAssets))
                            } label: {
                                Label("Assets", systemImage: "chevron.left")
                            }
                            .dashboardControl()
                        }

                        if let header = page.header, let price = header.price {
                            DashboardCard {
                                HStack(alignment: .firstTextBaseline) {
                                    DashboardMetricBlock(
                                        title: "Price",
                                        value: AssetDetailFormat.currency(price, code: currencyCode))
                                    Spacer()
                                    if let change = header.fraction24h {
                                        HStack(spacing: 4) {
                                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                            Text(AssetDetailFormat.change(change))
                                        }
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(change >= 0 ? PortuTheme.dashboardSuccess : PortuTheme.dashboardWarning)
                                    }
                                }
                            }
                        }

                        AssetPriceChart(assetId: assetId, coinGeckoId: page.chartPriceID, store: store)
                            .dashboardCard()
                        AssetHoldingsSummary(holdings: page.holdings, currencyCode: currencyCode)
                            .dashboardCard()
                        AssetPositionsTable(rows: page.rows, currencyCode: currencyCode)
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
