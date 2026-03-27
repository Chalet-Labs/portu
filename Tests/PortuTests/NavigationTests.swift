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

    @Test func contentViewRoutesAllPositionsSectionToDedicatedWorkspace() {
        if case .placeholder = ContentView.destination(for: .allPositions) {
            Issue.record("All Positions still routes to a placeholder destination.")
        }
    }

    @Test func positionFilterSidebarExposesTypeAndProtocolFilters() throws {
        let snapshot = PositionFilterSidebar.makeSnapshot(
            selectedPositionFilter: .lending,
            selectedProtocol: "Aave V3",
            positionFilterTotals: [
                .all: 4_000,
                .idle: 2_800,
                .lending: 1_200
            ],
            protocolOptions: ["Aave V3", "Euler"]
        )

        let lendingRow = try #require(
            snapshot.positionTypeRows.first(where: { $0.filter == .lending })
        )

        #expect(lendingRow.title == "Lending")
        #expect(lendingRow.total == 1_200)
        #expect(lendingRow.isSelected)
        #expect(snapshot.protocolRows.map(\.title) == ["All Protocols", "Aave V3", "Euler"])
        #expect(snapshot.protocolRows[0].isSelected == false)
        #expect(snapshot.protocolRows[1].isSelected)
    }
}
