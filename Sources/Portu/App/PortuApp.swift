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

        #if DEBUG
            let debugEnabled = DebugMode.isEnabled()
            let session: URLSession = debugEnabled ? NetworkLogger.debugSession() : .shared
        #else
            let session: URLSession = .shared
        #endif

        let syncEngine = SyncEngine(
            modelContext: container.mainContext,
            providerFactory: ProviderFactory(secretStore: KeychainService(), session: session))
        let priceService = PriceService(session: session)

        self.store = Store(initialState: AppFeature.State(storeIsEphemeral: isEphemeral)) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine = .live(engine: syncEngine)
            $0.priceService = .live(service: priceService)
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
                    priceService: .live(service: priceService))
                // App.init is implicitly @MainActor via App protocol conformance
                let state = appState
                Task { @MainActor in
                    do {
                        try await debugServer.start()
                        state.debugServer = debugServer
                    } catch {
                        state.debugServer = nil
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
        .modelContainer(container)

        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(container)
    }
}
