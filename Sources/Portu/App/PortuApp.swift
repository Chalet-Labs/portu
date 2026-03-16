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
                for: Portfolio.self, Account.self, Holding.self, Asset.self
            )
        } catch {
            // Schema migration failed — fall back to an in-memory store so the
            // app can still launch. A future release should surface a user-facing
            // alert prompting to reset the database.
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(
                    for: Portfolio.self, Account.self, Holding.self, Asset.self,
                    configurations: config
                )
            } catch {
                fatalError("Failed to create even an in-memory ModelContainer: \(error)")
            }
        }
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
