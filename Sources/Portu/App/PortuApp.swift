import ComposableArchitecture
import Foundation
import os
import PortuCore
import PortuNetwork
import PortuUI
import SwiftData
import SwiftUI

final class MigratingSecretStore: SecretStore, @unchecked Sendable {
    private let source: any SecretStore
    private let destination: any SecretStore
    private let lock = NSRecursiveLock()

    init(source: any SecretStore, destination: any SecretStore) {
        self.source = source
        self.destination = destination
    }

    func get(key: KeychainKey) throws(KeychainError) -> String? {
        try withLock {
            do {
                if let value = try destination.get(key: key) {
                    return value
                }
            } catch let destinationError as KeychainError {
                if let sourceValue = try? source.get(key: key) {
                    return sourceValue
                }
                throw destinationError
            }
            return try source.get(key: key)
        }
    }

    func set(key: KeychainKey, value: String) throws(KeychainError) {
        try withLock {
            try destination.set(key: key, value: value)
            try source.delete(key: key)
        }
    }

    func delete(key: KeychainKey) throws(KeychainError) {
        try withLock {
            try destination.delete(key: key)
            try source.delete(key: key)
        }
    }

    func migrate(
        keys: [KeychainKey],
        retiredKeys: Set<KeychainKey>) throws(KeychainError) {
        try withLock {
            var firstError: KeychainError?
            for key in retiredKeys.sorted(by: { $0.rawKey < $1.rawKey }) {
                do {
                    try source.delete(key: key)
                } catch let error as KeychainError {
                    firstError = firstError ?? error
                } catch {
                    firstError = firstError ?? .encodingFailed
                }
            }
            do {
                try SecretStoreMigration.migrate(
                    keys: keys,
                    from: source,
                    to: destination)
            } catch let error as KeychainError {
                firstError = firstError ?? error
            } catch {
                firstError = firstError ?? .encodingFailed
            }
            if let firstError {
                throw firstError
            }
        }
    }

    private func withLock<T>(
        _ operation: () throws -> T) throws(KeychainError) -> T {
        lock.lock()
        defer { lock.unlock() }
        do {
            return try operation()
        } catch let error as KeychainError {
            throw error
        } catch {
            throw .encodingFailed
        }
    }
}

private actor SecretMigrationCoordinator {
    let store: MigratingSecretStore

    init(store: MigratingSecretStore) {
        self.store = store
    }

    func migrate(
        keys: [KeychainKey],
        retiredKeys: Set<KeychainKey>) throws(KeychainError) {
        try store.migrate(keys: keys, retiredKeys: retiredKeys)
    }
}

actor APIKeyAvailabilityReader {
    private let secretStore: any SecretStore

    init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    func hasAPIKey(_ key: KeychainKey) throws -> Bool {
        let value = try secretStore.get(key: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false
    }
}

@main
struct PortuApp: App {
    let store: StoreOf<AppFeature>
    @State private var appState = AppState()
    let container: ModelContainer
    let secretStore: any SecretStore

    // swiftlint:disable:next function_body_length
    init() {
        let factory = ModelContainerFactory()
        let isEphemeral: Bool

        do {
            let bootstrap = try factory.bootstrap()
            self.container = bootstrap.container
            isEphemeral = bootstrap.isEphemeral
        } catch {
            fatalError("Failed to create even an in-memory ModelContainer: \(error)")
        }

        do {
            try PortfolioCategorySeeder.seedIfNeeded(in: container.mainContext)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app", category: "PortfolioCategorySeeder")
                .error("Portfolio category seeding failed: \(String(describing: error), privacy: .public)")
        }

        do {
            try HistoricalPriceIDMigrator.migrate(
                in: container.mainContext,
                storeIsEphemeral: isEphemeral)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app", category: "HistoricalPriceIDMigrator")
                .error("Historical price ID migration failed: \(String(describing: error), privacy: .public)")
        }

        do {
            try ZapperToZerionMigrator.migrate(in: container.mainContext)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app", category: "ZapperToZerionMigrator")
                .error("Account provider migration failed: \(String(describing: error), privacy: .public)")
        }

        #if DEBUG
            let debugEnabled = DebugMode.isEnabled()
            let session: URLSession = debugEnabled ? NetworkLogger.debugSession() : .shared
        #else
            let session: URLSession = .shared
        #endif

        let modelContext = container.mainContext
        ProviderIntervalSettings.migrateLegacyPreferences()
        let secretStore = MigratingSecretStore(
            source: LocalSecretStore(),
            destination: Self.makeSecretStore())
        self.secretStore = secretStore
        let secretMigrationKeys = Self.secretMigrationKeys(modelContext: modelContext)
        Task {
            do {
                try await Self.migrateSecrets(
                    keys: secretMigrationKeys,
                    using: secretStore)
            } catch {
                Self.keychainAccessLogger.error(
                    "Plaintext secret migration stopped safely: \(String(describing: error), privacy: .public)")
            }
        }
        let zerionClient = ZerionAPIClient(
            apiKey: { try secretStore.get(key: .providerAPIKey(.zerion)) ?? "" },
            session: session)
        let zerionProvider = ZerionProvider(client: zerionClient)
        let syncEngine = SyncEngine(
            modelContext: modelContext,
            providerFactory: ProviderFactory(
                secretStore: secretStore,
                session: session,
                zerionProvider: zerionProvider))
        let priceService = PriceService(session: session) {
            Self.coinGeckoAPIKey(from: secretStore)
        }
        let priceServiceClient = Self.makePriceServiceClient(
            priceService: priceService,
            secretStore: secretStore,
            zerionProvider: zerionProvider)

        let displayCurrencyPreference = DisplayCurrencyPreferenceClient.liveValue
        // Restore a saved non-USD currency as pending and start on USD; the launch FX
        // request commits it once a real rate is known, and a failure stays on USD.
        let savedCurrency = displayCurrencyPreference.load()
        self.store = Store(initialState: AppFeature.State(
            selectedCurrency: .usd,
            pendingCurrency: savedCurrency == .usd ? nil : savedCurrency,
            storeIsEphemeral: isEphemeral)) {
                AppFeature()
            } withDependencies: {
                $0.continuousClock = ContinuousClock()
                $0.syncEngine = .live(engine: syncEngine)
                $0.priceService = priceServiceClient
                $0.displayCurrencyPreference = displayCurrencyPreference
                $0.currencyConversion = .live(
                    modelContext: modelContext,
                    priceService: priceServiceClient)
                $0.historicalPriceBackfill = .live(
                    modelContext: modelContext,
                    priceService: priceServiceClient,
                    dashboardSettings: { TokenDashboardSettings.fromDefaults() })
            }

        // Bridge: features can trigger sync via AppState until migrated to TCA
        appState.onSyncRequested = { [store] in
            store.send(.syncTapped)
        }
        appState.observe(store)

        #if DEBUG
            if debugEnabled {
                let debugServer = DebugServer(
                    port: DebugMode.port(),
                    modelContainer: container,
                    store: store,
                    priceService: priceServiceClient)
                // App.init is implicitly @MainActor via App protocol conformance
                let state = appState
                Task { @MainActor in
                    do {
                        try await debugServer.start()
                        state.debugServer = debugServer
                    } catch {
                        state.debugServerStartFailed = true
                        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app", category: "DebugServer")
                            .error("Debug server failed to start: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        #endif
    }

    var body: some Scene {
        Window("Portu", id: "main") {
            ContentView(store: store, secretStore: secretStore)
                .environment(appState)
        }
        .defaultWindowPlacement { _, context in
            let launchSize = MainWindowPlacement.launchSize(for: context.defaultDisplay.visibleRect.size)
            return WindowPlacement(size: launchSize)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    store.send(.settingsSelected)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private static func makePriceServiceClient(
        priceService: PriceService,
        secretStore: any SecretStore,
        zerionProvider: ZerionProvider) -> PriceServiceClient {
        let apiKeyAvailability = APIKeyAvailabilityReader(secretStore: secretStore)
        return PriceServiceClient(
            fetchPrices: { coinIds in
                try await LivePriceUpdateBuilder.fetchPrices(
                    coinIds: coinIds,
                    priceService: priceService) { identities in
                        guard
                            !identities.isEmpty,
                            try await apiKeyAvailability.hasAPIKey(.providerAPIKey(.zerion))
                        else {
                            return PricePollingIDResolver.emptyUpdate
                        }
                        return try await zerionProvider.fetchPriceUpdate(for: identities)
                    }
            },
            fetchCoinGeckoPrices: { request, currency, usdToDisplayRate in
                let update = try await LivePriceUpdateBuilder.fetchCoinGeckoPrices(
                    request: request,
                    priceService: priceService,
                    currency: .usd)
                guard currency != .usd else { return update }
                return update.convertedUSDValues(to: currency, rate: usdToDisplayRate, preserveChanges24h: true)
            },
            fetchOnchainFallbackPrices: { identities, currency, usdToDisplayRate in
                guard
                    !identities.isEmpty,
                    try await apiKeyAvailability.hasAPIKey(.providerAPIKey(.zerion))
                else {
                    return PricePollingIDResolver.emptyUpdate(currency: currency)
                }
                let update = try await zerionProvider.fetchPriceUpdate(for: identities)
                guard currency != .usd else { return update }
                return update.convertedUSDValues(
                    to: currency,
                    rate: usdToDisplayRate,
                    preserveChanges24h: true)
            },
            fetchHistoricalPrices: { coinId, days in
                try await priceService.fetchHistoricalPrices(for: coinId, days: days)
            },
            fetchHistoricalPricesForCurrency: { coinId, currency, days in
                try await priceService.fetchHistoricalPrices(for: coinId, currency: currency, days: days)
            },
            fetchCurrentUSDConversionRate: { currency in
                try await priceService.fetchCurrentUSDConversionRate(to: currency)
            },
            fetchHistoricalUSDConversionRates: { currency, days in
                try await priceService.fetchHistoricalUSDConversionRates(to: currency, days: days)
            },
            resolveCoinGeckoIDs: { identities in
                try await priceService.resolveCoinGeckoIDs(for: identities)
            },
            fetchOnchainHistoricalPrices: { identity, days in
                guard try await apiKeyAvailability.hasAPIKey(.providerAPIKey(.zerion)) else {
                    throw PriceServiceClient.ClientError.onchainProviderUnavailable
                }
                return try await zerionProvider.fetchHistoricalPrices(identity: identity, days: days)
            },
            canFetchOnchainHistoricalPrices: {
                try await apiKeyAvailability.hasAPIKey(.providerAPIKey(.zerion))
            },
            invalidateCache: { await priceService.invalidateCache() })
    }

    nonisolated static func zerionAPIKey(from secretStore: any SecretStore) throws -> String? {
        let value = try secretStore.get(key: .providerAPIKey(.zerion))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    nonisolated static func zerionAPIKeyIfAvailable(from secretStore: any SecretStore) -> String? {
        readAPIKey(named: "Zerion", from: secretStore, key: .providerAPIKey(.zerion))
    }

    nonisolated static func secretStoreService(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.portu.app") -> String {
        environment["XCTestConfigurationFilePath"] == nil
            ? bundleIdentifier
            : "\(bundleIdentifier).tests"
    }

    nonisolated static func makeSecretStore(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.portu.app",
        factory: (String) -> any SecretStore = { KeychainService(service: $0) }) -> any SecretStore {
        factory(secretStoreService(
            environment: environment,
            bundleIdentifier: bundleIdentifier))
    }

    nonisolated static func migrateSecrets(
        keys: [KeychainKey],
        retiredKeys: Set<KeychainKey> = retiredPlaintextSecretKeys,
        using store: MigratingSecretStore) async throws(KeychainError) {
        try await SecretMigrationCoordinator(store: store).migrate(
            keys: keys,
            retiredKeys: retiredKeys)
    }

    nonisolated static func coinGeckoAPIKey(from secretStore: any SecretStore) -> String? {
        readAPIKey(named: "CoinGecko", from: secretStore, key: .serviceAPIKey("coingecko"))
    }

    nonisolated private static let keychainAccessLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app",
        category: "KeychainAccess")

    nonisolated static let providerSecretMigrationKeys: Set<KeychainKey> = [
        .providerAPIKey(.zerion),
        .serviceAPIKey("coingecko"),
        .serviceAPIKey("debank")
    ]

    nonisolated static let retiredPlaintextSecretKeys: Set<KeychainKey> = [
        .providerAPIKey(.zapper)
    ]

    @MainActor
    private static func secretMigrationKeys(modelContext: ModelContext) -> [KeychainKey] {
        // Retired plaintext credentials are deleted separately without copying
        // them into the destination Keychain.
        var keys = providerSecretMigrationKeys
        for chain in Chain.allCases {
            keys.insert(.rpcEndpoint(chain))
        }
        if let accounts = try? modelContext.fetch(FetchDescriptor<Account>()) {
            for account in accounts {
                keys.insert(.exchangeAPIKey(account.id))
                keys.insert(.exchangeAPISecret(account.id))
                keys.insert(.exchangePassphrase(account.id))
            }
        }
        return keys.sorted { $0.rawKey < $1.rawKey }
    }

    nonisolated private static func readAPIKey(
        named provider: String,
        from secretStore: any SecretStore,
        key: KeychainKey) -> String? {
        do {
            let value = try secretStore.get(key: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        } catch {
            // Important: distinguish "no key configured" (returns nil, no log) from
            // "keychain retrieval failed" (returns nil, but log so users can diagnose
            // locked-keychain or migration scenarios).
            keychainAccessLogger.error(
                "Failed to read \(provider, privacy: .public) API key from keychain: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
