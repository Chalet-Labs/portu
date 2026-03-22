// Sources/Portu/Features/AllAssets/AllAssetsView.swift
import SwiftUI

struct AllAssetsView: View {
    @State private var selectedTab: AssetTab = .assets

    enum AssetTab: String, CaseIterable {
        case assets = "Assets"
        case nfts = "NFTs"
        case platforms = "Platforms"
        case networks = "Networks"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(AssetTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .assets: AssetsTab()
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
            description: Text("NFT tracking coming soon")
        )
    }
}
