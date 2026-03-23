import SwiftUI

struct NFTPlaceholderTabView: View {
    static let placeholderText = "NFT tracking coming soon"

    var body: some View {
        ContentUnavailableView(Self.placeholderText, systemImage: "photo.stack")
    }
}
