import SwiftUI

public enum PortuTheme {
    public static let gainColor = Color.green
    public static let lossColor = Color.red
    public static let neutralColor = Color.secondary

    /// Returns gain/loss color based on a value being positive, negative, or zero.
    public static func changeColor(for value: Decimal) -> Color {
        if value > 0 { gainColor }
        else if value < 0 { lossColor }
        else { neutralColor }
    }
}
