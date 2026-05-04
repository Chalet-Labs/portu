import SwiftUI

public enum PortuTheme {
    public static let gainColor = Color.green
    public static let lossColor = Color.red
    public static let neutralColor = Color.secondary

    public static let dashboardBackground = Color(red: 0.045, green: 0.043, blue: 0.039)
    public static let dashboardSidebarBackground = Color(red: 0.110, green: 0.095, blue: 0.088)
    public static let dashboardPanelBackground = Color(red: 0.072, green: 0.068, blue: 0.060)
    public static let dashboardPanelElevatedBackground = Color(red: 0.105, green: 0.096, blue: 0.084)
    public static let dashboardMutedPanelBackground = Color(red: 0.135, green: 0.123, blue: 0.108)
    public static let dashboardStroke = Color(red: 0.178, green: 0.160, blue: 0.135)
    public static let dashboardMutedStroke = Color(red: 0.240, green: 0.212, blue: 0.170)
    public static let dashboardGold = Color(red: 0.690, green: 0.550, blue: 0.310)
    public static let dashboardGoldMuted = Color(red: 0.360, green: 0.285, blue: 0.175)
    public static let dashboardText = Color(red: 0.910, green: 0.885, blue: 0.820)
    public static let dashboardSecondaryText = Color(red: 0.610, green: 0.570, blue: 0.500)
    public static let dashboardTertiaryText = Color(red: 0.390, green: 0.355, blue: 0.305)
    public static let dashboardWarning = Color(red: 0.860, green: 0.330, blue: 0.330)
    public static let dashboardSuccess = Color(red: 0.360, green: 0.730, blue: 0.455)

    public static let dashboardSidebarWidth: CGFloat = 164
    public static let dashboardInspectorWidth: CGFloat = 318
    public static let dashboardPanelCornerRadius: CGFloat = 8
    public static let dashboardContentSpacing: CGFloat = 12
    public static let dashboardTableRowHeight: CGFloat = 24

    /// Returns gain/loss color based on a value being positive, negative, or zero.
    public static func changeColor(for value: Decimal) -> Color {
        if value > 0 { gainColor } else if value < 0 { lossColor } else { neutralColor }
    }
}
