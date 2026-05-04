import PortuCore
import PortuUI
import SwiftUI

struct AssetMetadataSidebar: View {
    let asset: Asset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let logoURL = asset.logoURL, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "bitcoinsign.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(DashboardStyle.sectionTitleFont)
                        .foregroundStyle(PortuTheme.dashboardText)
                    Text(asset.symbol)
                        .font(.caption)
                        .foregroundStyle(PortuTheme.dashboardSecondaryText)
                }

                Rectangle().fill(PortuTheme.dashboardStroke).frame(height: 1)

                LabeledContent("Category") {
                    CapsuleBadge(asset.category.rawValue.capitalized)
                }

                LabeledContent("Verified") {
                    Image(systemName: asset.isVerified ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(asset.isVerified ? PortuTheme.dashboardSuccess : PortuTheme.dashboardSecondaryText)
                }

                if let cgId = asset.coinGeckoId {
                    LabeledContent("CoinGecko") {
                        Text(cgId).font(.caption).foregroundStyle(PortuTheme.dashboardSecondaryText)
                    }
                }

                Rectangle().fill(PortuTheme.dashboardStroke).frame(height: 1)

                Text("Explorer links are per-position (varies by network), not per-asset.")
                    .font(.caption)
                    .foregroundStyle(PortuTheme.dashboardTertiaryText)
            }
            .padding()
        }
        .font(.caption)
        .foregroundStyle(PortuTheme.dashboardSecondaryText)
        .background(PortuTheme.dashboardPanelBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(PortuTheme.dashboardStroke)
                .frame(width: 1)
        }
    }
}
