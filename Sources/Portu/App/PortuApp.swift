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
        container = try! ModelContainer(
            for: Portfolio.self, Account.self, Holding.self, Asset.self
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
