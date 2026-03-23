import SwiftData
import SwiftUI
import PortuCore

struct AllAssetsView: View {
    static let navigationTitle = "All Assets"

    @Environment(AppState.self) private var appState
    @Query private var positions: [Position]

    @State private var selectedTab: AllAssetsTab = .assets
    @State private var searchText = ""
    @State private var grouping: AllAssetsGrouping = .category

    private var viewModel: AllAssetsViewModel {
        let viewModel = AllAssetsViewModel(
            positions: positions,
            livePrices: appState.prices
        )
        viewModel.selectedTab = selectedTab
        viewModel.searchText = searchText
        viewModel.grouping = grouping
        return viewModel
    }

    var body: some View {
        let viewModel = viewModel

        TabView(selection: $selectedTab) {
            AssetsTabView(
                rows: viewModel.assetRows,
                groups: viewModel.groupedAssetRows,
                searchText: $searchText,
                grouping: $grouping
            )
                .tabItem {
                    Label(AllAssetsTab.assets.title, systemImage: AllAssetsTab.assets.systemImage)
                }
                .tag(AllAssetsTab.assets)

            placeholderTab(
                title: "NFT tracking coming soon",
                message: "NFT tracking will land in a follow-on task.",
                systemImage: AllAssetsTab.nfts.systemImage
            )
            .tabItem {
                Label(AllAssetsTab.nfts.title, systemImage: AllAssetsTab.nfts.systemImage)
            }
            .tag(AllAssetsTab.nfts)

            PlatformsTabView(rows: viewModel.platformRows)
                .tabItem {
                    Label(AllAssetsTab.platforms.title, systemImage: AllAssetsTab.platforms.systemImage)
                }
                .tag(AllAssetsTab.platforms)

            NetworksTabView(rows: viewModel.networkRows)
                .tabItem {
                    Label(AllAssetsTab.networks.title, systemImage: AllAssetsTab.networks.systemImage)
                }
                .tag(AllAssetsTab.networks)
        }
        .navigationTitle(Self.navigationTitle)
    }

    @ViewBuilder
    private func placeholderTab(
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
