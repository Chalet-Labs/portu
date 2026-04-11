import ComposableArchitecture
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

        let syncEngine = SyncEngine(
            modelContext: container.mainContext,
            providerFactory: ProviderFactory(secretStore: KeychainService()))
        let priceService = PriceService()

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
