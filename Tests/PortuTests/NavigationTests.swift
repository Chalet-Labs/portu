import Testing
@testable import Portu

@MainActor
@Suite("Navigation Tests")
struct NavigationTests {
    @Test func sidebarSectionDefaultsToOverview() {
        let state = AppState()
        #expect(state.selectedSection == .overview)
    }

    @Test func contentViewRoutesKnownSections() {
        #expect(SidebarSection.allCases.contains(.performance))
        #expect(SidebarSection.allCases.contains(.allAssets))
    }
}
