import Foundation
import os
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

    /// Attempts the persistent store, falling back to an ephemeral in-memory store on failure.
    /// A failure here means the app keeps running but stops persisting data, so it is reported
    /// via `onProductionOpenFailure` rather than swallowed.
    func bootstrap(
        onProductionOpenFailure: (any Error) -> Void = Self.logProductionOpenFailure) throws -> (container: ModelContainer, isEphemeral: Bool) {
        do {
            return try (makeForProduction(), false)
        } catch {
            onProductionOpenFailure(error)
            return try (makeInMemory(), true)
        }
    }

    private static func logProductionOpenFailure(_ error: any Error) {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app", category: "ModelContainerFactory")
            .error(
                "Persistent store open failed, falling back to in-memory storage: \(String(describing: error), privacy: .public)")
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
        ProviderPortfolioValuePoint.self,
        ProviderPortfolioHistoryRefresh.self,
        ProviderPnLSnapshot.self,
        ProviderPnLAssetBreakdown.self,
        PortfolioCategory.self,
        CategorySymbolRule.self,
        PortfolioSnapshot.self,
        AccountSnapshot.self,
        AssetSnapshot.self
    ])
}
