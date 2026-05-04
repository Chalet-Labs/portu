// Sources/Portu/Features/AllAssets/AllAssetsView.swift
import ComposableArchitecture
import PortuUI
import SwiftUI

struct AllAssetsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
            DashboardPageHeader("All Assets")

            Picker("Tab", selection: Binding(
                get: { store.allAssets.selectedTab },
                set: { store.send(.allAssets(.tabSelected($0))) })) {
                    ForEach(AssetTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                .dashboardControl()

            switch store.allAssets.selectedTab {
            case .assets: AssetsTab(store: store)
            case .nfts:
                nftPlaceholder
                    .dashboardCard()
            case .platforms:
                PlatformsTab()
                    .dashboardCard()
            case .networks:
                NetworksTab()
                    .dashboardCard()
            }
        }
        .padding(DashboardStyle.pagePadding)
        .dashboardPage()
    }

    private var nftPlaceholder: some View {
        ContentUnavailableView(
            "NFT Tracking",
            systemImage: "photo.artframe",
            description: Text("NFT tracking coming soon"))
            .foregroundStyle(PortuTheme.dashboardSecondaryText)
    }
}
