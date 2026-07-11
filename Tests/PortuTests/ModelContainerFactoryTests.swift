import Foundation
@testable import Portu
import Testing

@MainActor
struct ModelContainerFactoryTests {
    @Test func `production open failure leaves existing store artifacts intact`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PortuModelContainerFactoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appending(path: "Portu.store", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        let walURL = URL(fileURLWithPath: storeURL.path(percentEncoded: false) + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path(percentEncoded: false) + "-shm")
        try Data("wal sentinel".utf8).write(to: walURL)
        try Data("shm sentinel".utf8).write(to: shmURL)

        let factory = ModelContainerFactory(storeURL: storeURL)

        #expect(throws: (any Error).self) {
            _ = try factory.makeForProduction()
        }
        #expect(FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: walURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: shmURL.path(percentEncoded: false)))
    }
}
