import ComposableArchitecture
import PortuCore
import SwiftUI

/// The window's root. Its body reads no observable state, so a state change never re-creates the
/// dashboard from here. Everything that follows the selected section is in `DashboardView`.
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
        DashboardView(store: store, secretStore: secretStore)
            .frame(minWidth: 900, minHeight: 600)
            .task {
                store.send(.appLaunched)
                store.send(.startScheduledSync)
            }
            // The read model builds once and follows saves, settings and the day for as long as
            // the window is up.
            .task {
                await store.send(.portfolio(.task)).finish()
            }
            .onDisappear {
                store.send(.stopScheduledSync)
            }
    }
}
