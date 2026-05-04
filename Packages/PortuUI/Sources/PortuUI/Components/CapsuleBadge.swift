import SwiftUI

/// A small capsule-shaped label badge used for chain names, categories, and types.
public struct CapsuleBadge: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(PortuTheme.dashboardText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PortuTheme.dashboardMutedPanelBackground)
            .overlay(
                Capsule()
                    .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
            .clipShape(Capsule())
    }
}
