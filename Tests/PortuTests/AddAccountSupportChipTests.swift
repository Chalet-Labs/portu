@testable import Portu
import PortuUI
import Testing

@MainActor
struct AddAccountSupportChipTests {
    @Test func `model identity is stable for equivalent chips`() {
        let first = AddAccountSupportChip.Model(
            title: "Ethereum",
            systemImage: "link",
            tint: PortuTheme.dashboardGold)
        let second = AddAccountSupportChip.Model(
            title: "Ethereum",
            systemImage: "link",
            tint: PortuTheme.dashboardGold)

        #expect(first.id == second.id)
    }
}
