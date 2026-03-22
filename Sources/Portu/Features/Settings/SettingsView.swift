import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab("Accounts", systemImage: "building.columns") {
                AccountsSettingsTab()
            }
        }
        .frame(width: 450, height: 300)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage("refreshInterval") private var refreshInterval = 30.0
    @AppStorage("watchlistAssetCount") private var watchlistAssetCount = 5

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

            Section("Overview Watchlist") {
                Picker("Tracked assets", selection: $watchlistAssetCount) {
                    Text("3 assets").tag(3)
                    Text("5 assets").tag(5)
                    Text("8 assets").tag(8)
                    Text("10 assets").tag(10)
                }

                Text("Controls how many top portfolio assets appear in the Overview inspector watchlist.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

private struct AccountsSettingsTab: View {
    var body: some View {
        Form {
            Section("Exchange API Keys") {
                Text("Configure exchange connections here.")
                    .foregroundStyle(.secondary)
                // TODO: API key management forms
            }

            Section("Wallet Addresses") {
                Text("Add wallet addresses for on-chain tracking.")
                    .foregroundStyle(.secondary)
                // TODO: Wallet address management
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
    }
}
