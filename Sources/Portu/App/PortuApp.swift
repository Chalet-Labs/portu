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

        let secretStore = KeychainService()
        let modelContext = container.mainContext
        let syncEngine = SyncEngine(
            modelContext: modelContext,
            providerFactory: ProviderFactory(secretStore: secretStore, session: session))
        let priceService = PriceService(session: session) {
            try? secretStore.get(key: .serviceAPIKey("coingecko"))
        }
        let priceServiceClient = PriceServiceClient.live(service: priceService)

        self.store = Store(initialState: AppFeature.State(storeIsEphemeral: isEphemeral)) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine = .live(engine: syncEngine)
            $0.priceService = priceServiceClient
            $0.historicalPriceBackfill = .live(
                modelContext: modelContext,
                priceService: priceServiceClient)
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
}
