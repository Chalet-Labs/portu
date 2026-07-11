import Foundation
import PortuCore
import SwiftData

struct ModelContainerFactory {
    private let fileManager: FileManager
    private let storeURL: URL?

    init(fileManager: FileManager = .default, storeURL: URL? = nil) {
        self.fileManager = fileManager
        self.storeURL = storeURL
    }

    func makeForProduction() throws -> ModelContainer {
        let storeURL = try persistentStoreURL()
        return try makePersistentContainer(at: storeURL)
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
        if let storeURL {
            return storeURL
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Could not find Application Support directory"])
        }
        let directory = appSupport.appending(path: "Portu", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Portu.store")
    }

    static let schema = Schema([
        Account.self,
        WalletAddress.self,
        Position.self,
        PositionToken.self,
        Asset.self,
        TokenPricingOverride.self,
        TokenIdentityMapping.self,
        HistoricalPricePoint.self,
        CurrencyConversionRatePoint.self,
        PortfolioCategory.self,
        CategorySymbolRule.self,
        PortfolioSnapshot.self,
        AccountSnapshot.self,
        AssetSnapshot.self
    ])
}
