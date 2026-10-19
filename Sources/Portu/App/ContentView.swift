import ComposableArchitecture
import PortuCore
import SwiftUI

/// The window's root. Its body reads no observable state, store or app: a read here would re-run
/// it on every change of that state, re-create the `ActivePortfolioProvider` and make it re-fetch
/// and walk the whole portfolio. Everything that follows the selected section is in
/// `DashboardView`.
struct ContentView: View {
    let store: StoreOf<AppFeature>
    let secretStore: any SecretStore

    init(
        store: StoreOf<AppFeature>,
        secretStore: any SecretStore = PortuApp.makeSecretStore()) {
        self.store = store
        self.secretStore = secretStore
    }

    var body: some View {
        ActivePortfolioProvider {
            DashboardView(store: store, secretStore: secretStore)
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            store.send(.appLaunched)
            store.send(.startScheduledSync)
        }
        .onDisappear {
            store.send(.stopScheduledSync)
        }
    }
}
