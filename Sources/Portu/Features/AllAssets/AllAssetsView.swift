// Sources/Portu/Features/AllAssets/AllAssetsView.swift
import ComposableArchitecture
import SwiftUI

struct AllAssetsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: Binding(
                get: { store.allAssets.selectedTab },
                set: { store.send(.allAssets(.tabSelected($0))) })) {
                    ForEach(AssetTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

            switch store.allAssets.selectedTab {
            case .assets: AssetsTab(store: store)
            case .nfts: nftPlaceholder
            case .platforms: PlatformsTab()
            case .networks: NetworksTab()
            }
        }
        .navigationTitle("All Assets")
    }

    private var nftPlaceholder: some View {
        ContentUnavailableView(
            "NFT Tracking",
            systemImage: "photo.artframe",
            description: Text("NFT tracking coming soon"))
    }
}
