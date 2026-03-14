import SwiftUI
import SwiftData
import PortuCore
import PortuNetwork
import PortuUI

@main
struct PortuApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(for: [
            Portfolio.self,
            Account.self,
            Holding.self,
            Asset.self,
        ])

        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(for: [
            Portfolio.self,
            Account.self,
            Holding.self,
            Asset.self,
        ])
    }
}
