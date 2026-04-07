import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab("API Keys", systemImage: "key.fill") {
                APIKeysSettingsTab()
            }
        }
        .frame(width: 450, height: 400)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage("refreshInterval") private var refreshInterval = 30.0

    var body: some View {
        Form {
            Section("Price Updates") {
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
