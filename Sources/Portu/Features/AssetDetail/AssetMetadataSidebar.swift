import PortuCore
import SwiftUI

struct AssetMetadataSidebar: View {
    let asset: Asset

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Logo
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

                // Name and symbol
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name).font(.title3.weight(.semibold))
                    Text(asset.symbol).font(.body).foregroundStyle(.secondary)
                }

                Divider()

                // Category
                LabeledContent("Category") {
                    Text(asset.category.rawValue.capitalized)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                // Verification
                LabeledContent("Verified") {
                    Image(systemName: asset.isVerified ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(asset.isVerified ? .green : .secondary)
                }

                // CoinGecko ID
                if let cgId = asset.coinGeckoId {
                    LabeledContent("CoinGecko") {
                        Text(cgId).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Explorer links note
                Text("Explorer links are per-position (varies by network), not per-asset.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
    }
}
