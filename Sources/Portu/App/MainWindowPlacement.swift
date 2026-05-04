import CoreGraphics

enum MainWindowPlacement {
    private static let displayScale: CGFloat = 0.9
    private static let minimumSize = CGSize(width: 900, height: 600)
    private static let maximumSize = CGSize(width: 1440, height: 960)

    static func launchSize(for visibleDisplaySize: CGSize) -> CGSize {
        CGSize(
            width: clamped(
                visibleDisplaySize.width * displayScale,
                minimum: minimumSize.width,
                maximum: maximumSize.width),
            height: clamped(
                visibleDisplaySize.height * displayScale,
                minimum: minimumSize.height,
                maximum: maximumSize.height))
    }

    private static func clamped(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}
