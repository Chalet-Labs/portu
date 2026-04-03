@testable import PortuUI
import Testing

struct PortuUITests {
    @Test func `theme colors`() {
        #expect(PortuTheme.changeColor(for: 1.0) == PortuTheme.gainColor)
        #expect(PortuTheme.changeColor(for: -1.0) == PortuTheme.lossColor)
        #expect(PortuTheme.changeColor(for: 0) == PortuTheme.neutralColor)
    }
}
