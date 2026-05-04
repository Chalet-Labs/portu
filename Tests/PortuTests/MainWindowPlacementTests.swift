@testable import Portu
import Testing

struct MainWindowPlacementTests {
    @Test func `large displays clamp to maximum launch size`() {
        let size = MainWindowPlacement.launchSize(for: .init(width: 2560, height: 1440))

        #expect(size == .init(width: 1440, height: 960))
    }

    @Test func `normal displays use ninety percent launch size`() {
        let size = MainWindowPlacement.launchSize(for: .init(width: 1200, height: 900))

        #expect(size == .init(width: 1080, height: 810))
    }

    @Test func `small displays clamp to minimum launch size`() {
        let size = MainWindowPlacement.launchSize(for: .init(width: 800, height: 500))

        #expect(size == .init(width: 900, height: 600))
    }
}
