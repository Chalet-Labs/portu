@testable import PortuUI
import Testing

struct PortuUITests {
    @Test func `theme colors`() {
        #expect(PortuTheme.changeColor(for: 1.0) == PortuTheme.gainColor)
        #expect(PortuTheme.changeColor(for: -1.0) == PortuTheme.lossColor)
        #expect(PortuTheme.changeColor(for: 0) == PortuTheme.neutralColor)
    }

    @Test func `dashboard metrics stay compact for dense macOS views`() {
        #expect(PortuTheme.dashboardSidebarWidth == 164)
        #expect(PortuTheme.dashboardPanelCornerRadius <= 8)
        #expect(PortuTheme.dashboardContentSpacing == 12)
        #expect(PortuTheme.dashboardTableRowHeight <= 26)
    }
}
