@testable import Portu
import Testing

struct SidebarLayoutTests {
    @Test func `settings lives in bottom footer outside navigation sections`() {
        let navigationItems = SidebarLayout.navigationSections.flatMap(\.items)

        #expect(!navigationItems.contains(.settings))
        #expect(SidebarLayout.footerItems == [.settings])
    }

    @Test func `navigation sections hold only navigable destinations`() {
        let navigationItems = SidebarLayout.navigationSections.flatMap(\.items)

        #expect(navigationItems.allSatisfy { item in
            if case .section = item {
                true
            } else {
                false
            }
        })
    }
}
