import SwiftUI
import SwiftData
import PortuCore
import PortuNetwork
import PortuUI

@main
struct PortuApp: App {
    @State private var appState = AppState()
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Account.self, WalletAddress.self, Position.self, PositionToken.self,
                Asset.self, PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self
            )
        } catch {
            // Schema migration failed — fall back to an in-memory store so the
            // app can still launch. A future release should surface a user-facing
            // alert prompting to reset the database.
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(
                    for: Account.self, WalletAddress.self, Position.self, PositionToken.self,
                    Asset.self, PortfolioSnapshot.self, AccountSnapshot.self, AssetSnapshot.self,
                    configurations: config
                )
                appState.storeIsEphemeral = true
            } catch {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }

        appState.syncEngine = SyncEngine(
            modelContext: container.mainContext,
            appState: appState,
            secretStore: KeychainService()
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
