import ComposableArchitecture
import os
import PortuCore
import PortuNetwork
import PortuUI
import SwiftData
import SwiftUI

@main
struct PortuApp: App {
    let store: StoreOf<AppFeature>
    @State private var appState = AppState()
    let container: ModelContainer

    init() {
        let factory = ModelContainerFactory()
        var isEphemeral = false

        do {
            self.container = try factory.makeForProduction()
        } catch {
            do {
                self.container = try factory.makeInMemory()
                isEphemeral = true
            } catch {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }

        do {
            try PortfolioCategorySeeder.seedIfNeeded(in: container.mainContext)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app", category: "PortfolioCategorySeeder")
                .error("Portfolio category seeding failed: \(String(describing: error), privacy: .public)")
        }

        #if DEBUG
            let debugEnabled = DebugMode.isEnabled()
            let session: URLSession = debugEnabled ? NetworkLogger.debugSession() : .shared
        #else
            let session: URLSession = .shared
        #endif

        let secretStore = LocalSecretStore()
        let modelContext = container.mainContext
        let syncEngine = SyncEngine(
            modelContext: modelContext,
            providerFactory: ProviderFactory(secretStore: secretStore, session: session))
        let priceService = PriceService(session: session) {
            Self.coinGeckoAPIKey(from: secretStore)
        }
        let priceServiceClient = Self.makePriceServiceClient(
            priceService: priceService,
            secretStore: secretStore,
            session: session)

        self.store = Store(initialState: AppFeature.State(storeIsEphemeral: isEphemeral)) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = ContinuousClock()
            $0.syncEngine = .live(engine: syncEngine)
            $0.priceService = priceServiceClient
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
            ContentView(store: store)
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
        session: URLSession) -> PriceServiceClient {
        PriceServiceClient(
            fetchPrices: { coinIds in
                try await LivePriceUpdateBuilder.fetchPrices(
                    coinIds: coinIds,
                    priceService: priceService) { identities in
                        guard
                            !identities.isEmpty,
                            let apiKey = zapperAPIKey(from: secretStore)
                        else {
                            return PricePollingIDResolver.emptyUpdate
                        }
                        let zapperProvider = ZapperProvider(apiKey: apiKey, session: session)
                        return try await zapperProvider.fetchPriceUpdate(for: identities)
                    }
            },
            fetchHistoricalPrices: { coinId, days in
                try await priceService.fetchHistoricalPrices(for: coinId, days: days)
            },
            resolveCoinGeckoIDs: { identities in
                try await priceService.resolveCoinGeckoIDs(for: identities)
            },
            fetchZapperHistoricalPrices: { identity, days in
                guard let apiKey = zapperAPIKey(from: secretStore) else {
                    throw PriceServiceClient.ClientError.zapperProviderUnavailable
                }
                let zapperProvider = ZapperProvider(apiKey: apiKey, session: session)
                return try await zapperProvider.fetchHistoricalPrices(identity: identity, days: days)
            },
            canFetchZapperHistoricalPrices: { zapperAPIKey(from: secretStore) != nil },
            invalidateCache: { await priceService.invalidateCache() })
    }

    nonisolated static func zapperAPIKey(from secretStore: any SecretStore) -> String? {
        readAPIKey(named: "Zapper", from: secretStore, key: .providerAPIKey(.zapper))
    }

    nonisolated static func coinGeckoAPIKey(from secretStore: any SecretStore) -> String? {
        readAPIKey(named: "CoinGecko", from: secretStore, key: .serviceAPIKey("coingecko"))
    }

    private static let keychainAccessLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.portu.app",
        category: "KeychainAccess")

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
