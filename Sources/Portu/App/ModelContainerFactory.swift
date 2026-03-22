import Foundation
import SwiftData
import PortuCore

struct ModelContainerFactory {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    func makeForProduction() throws -> ModelContainer {
        let storeURL = try persistentStoreURL()

        do {
            return try makePersistentContainer(at: storeURL)
        } catch {
            try destroyStoreArtifacts(at: storeURL)
            return try makePersistentContainer(at: storeURL)
        }
    }

    func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Portu",
            schema: Self.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    private func makePersistentContainer(at storeURL: URL) throws -> ModelContainer {
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let configuration = ModelConfiguration(
            "Portu",
            schema: Self.schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    private func persistentStoreURL() throws -> URL {
        let directory = baseDirectoryURL.appending(path: "Portu", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Portu.store")
    }

    private func destroyStoreArtifacts(at storeURL: URL) throws {
        let candidateURLs = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
        ]

        for candidateURL in candidateURLs where fileManager.fileExists(atPath: candidateURL.path()) {
            try fileManager.removeItem(at: candidateURL)
        }
    }

    static let schema = Schema([
        Account.self,
        WalletAddress.self,
        Position.self,
        PositionToken.self,
        Asset.self,
        PortfolioSnapshot.self,
        AccountSnapshot.self,
        AssetSnapshot.self,
    ])
}
