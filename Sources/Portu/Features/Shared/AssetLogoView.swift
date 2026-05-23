import PortuUI
import SwiftUI

struct AssetLogoView: View {
    let symbol: String
    let logoURL: String?

    var body: some View {
        if let url = logoURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
            .clipShape(Circle())
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(PortuTheme.dashboardGoldMuted)
            Text(String(symbol.prefix(1)).uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(PortuTheme.dashboardGold)
        }
    }
}
