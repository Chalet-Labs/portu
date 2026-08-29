import ComposableArchitecture
import SwiftUI

struct UpdatesSettingsView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        SettingsPage(tab: .updates) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Updates",
                    subtitle: "Privacy-preserving update checks that notify without downloading or restarting.",
                    icon: .softwareUpdates) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsUpdateStatusNotice(
                                status: store.updaterStatus,
                                onDismiss: { store.send(.dismissUpdaterFailure) })

                            SettingsSwitchRow(
                                title: "Check for updates automatically",
                                subtitle: store.updaterStatus.updateSettingsSubtitle,
                                isOn: Binding(
                                    get: { store.updatePreferences.automaticallyChecksForUpdates },
                                    set: { store.send(.setAutomaticChecksEnabled($0)) }))
                                .disabled(!store.updaterStatus.isUpdaterEligible)

                            SettingsUpdateChannelPicker(store: store)
                                .disabled(!store.updaterStatus.isUpdaterEligible)

                            HStack {
                                Spacer()
                                Button {
                                    store.send(.checkForUpdatesTapped)
                                } label: {
                                    Label("Check for Updates Now", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!store.updaterStatus.canCheckForUpdates)
                            }
                        }
                    }

                SettingsInfoCard(
                    title: "Cryptographic Verification",
                    message: "Updates are checked against direct GitHub release artifacts with fail-closed Ed25519 signature verification.")
            }
        }
    }
}
