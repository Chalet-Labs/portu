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
            try? secretStore.get(key: .serviceAPIKey("coingecko"))
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
                let request = PricePollingIDResolver.split(coinIds)
                let coinGeckoUpdate = try await priceService.fetchPriceUpdate(for: request.coinGeckoIDs)
                guard
                    !request.zapperIdentities.isEmpty,
                    let apiKey = zapperAPIKey(from: secretStore)
                else {
                    return coinGeckoUpdate
                }
                let zapperProvider = ZapperProvider(apiKey: apiKey, session: session)
                let zapperUpdate = try await zapperProvider.fetchPriceUpdate(for: request.zapperIdentities)
                return PricePollingIDResolver.merge([coinGeckoUpdate, zapperUpdate])
            },
            fetchHistoricalPrices: { coinId, days in
                try await priceService.fetchHistoricalPrices(for: coinId, days: days)
            },
            resolveCoinGeckoIDs: { identities in
                try await priceService.resolveCoinGeckoIDs(for: identities)
            },
            fetchZapperHistoricalPrices: { identity, days in
                guard let apiKey = zapperAPIKey(from: secretStore) else {
                    return []
                }
                let zapperProvider = ZapperProvider(apiKey: apiKey, session: session)
                return try await zapperProvider.fetchHistoricalPrices(identity: identity, days: days)
            },
            canFetchZapperHistoricalPrices: { zapperAPIKey(from: secretStore) != nil },
            invalidateCache: { await priceService.invalidateCache() })
    }

    nonisolated static func zapperAPIKey(from secretStore: any SecretStore) -> String? {
        do {
            let apiKey = try secretStore.get(key: .providerAPIKey(.zapper))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return apiKey?.isEmpty == false ? apiKey : nil
        } catch {
            return nil
        }
    }
}
