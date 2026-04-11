import Foundation
import PortuCore
import SwiftData

struct ModelContainerFactory {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
            cloudKitDatabase: .none)
        return try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    private func makePersistentContainer(at storeURL: URL) throws -> ModelContainer {
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            "Portu",
            schema: Self.schema,
            url: storeURL,
            cloudKitDatabase: .none)
        return try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    private func persistentStoreURL() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Could not find Application Support directory"])
        }
        let directory = appSupport.appending(path: "Portu", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Portu.store")
    }

    private func destroyStoreArtifacts(at storeURL: URL) throws {
        let urls = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        for url in urls where fileManager.fileExists(atPath: url.path()) {
            try fileManager.removeItem(at: url)
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
        AssetSnapshot.self
    ])
}
