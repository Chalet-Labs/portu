@testable import Portu
import Testing

struct SidebarLayoutTests {
    @Test func `settings lives in bottom footer outside navigation sections`() {
        let navigationItems = SidebarLayout.navigationSections.flatMap(\.items)

        #expect(!navigationItems.contains(.settings))
        #expect(SidebarLayout.footerItems == [.settings])
    }
}
