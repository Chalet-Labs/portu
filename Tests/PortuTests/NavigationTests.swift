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

    @Test func contentViewRoutesAccountsSectionToAccountsWorkspace() {
        #expect(ContentView.destination(for: .accounts) == .accounts)
    }

    @Test func contentViewDeclaresAssetDestinationType() {
        #expect(ContentView.assetDestinationTypeName == "Asset.ID")
    }

    @Test func contentViewRoutesExposureSectionToDedicatedWorkspace() {
        if case .placeholder = ContentView.destination(for: .exposure) {
            Issue.record("Exposure still routes to a placeholder destination.")
        }
    }
}
