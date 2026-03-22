import Foundation
import SwiftData
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("Portu App Tests")
struct PortuAppTests {
    @Test func modelContainerFactoryFallsBackToDestructiveReset() throws {
        let baseDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let factory = ModelContainerFactory(baseDirectoryURL: baseDirectoryURL)
        let container = try factory.makeForProduction()

        let accounts = try container.mainContext.fetch(FetchDescriptor<Account>())
        #expect(accounts.isEmpty)
    }
}
