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
        var isEphemeral = false

        do {
            self.container = try ModelContainer(
                for: Account.self, WalletAddress.self, Position.self, PositionToken.self,
                Asset.self, PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
            )
        } catch {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                self.container = try ModelContainer(
                    for: Account.self, WalletAddress.self, Position.self, PositionToken.self,
                    Asset.self, PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self,
                    configurations: config
                )
                isEphemeral = true
            } catch {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }

        let syncEngine = SyncEngine(
            modelContext: container.mainContext,
            secretStore: KeychainService()
        )
        let priceService = PriceService()

        self.store = Store(initialState: AppFeature.State(storeIsEphemeral: isEphemeral)) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine = .live(engine: syncEngine)
            $0.priceService = .live(service: priceService)
        }

        // Bridge: features can trigger sync via AppState until migrated to TCA
        appState.storeIsEphemeral = isEphemeral
        appState.onSyncRequested = { [store] in
            store.send(.syncTapped)
        }
    }

    var body: some Scene {
        WindowGroup {
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
