#if DEBUG

    import SwiftUI

    struct DebugSettingsTab: View {
        @Environment(AppState.self) private var appState
        @AppStorage(DebugMode.enabledKey) private var isEnabled = false
        @AppStorage(DebugMode.portKey) private var port = Int(DebugMode.defaultPort)

        private var isRunning: Bool {
            appState.debugServer != nil
        }

        var body: some View {
            Form {
                Section("Debug Server") {
                    Toggle("Enable Debug Server", isOn: $isEnabled)

                    LabeledContent("Port") {
                        TextField("Port", value: $port, format: .number)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isRunning ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(isRunning ? "Running on port \(appState.debugServer?.port ?? DebugMode.defaultPort)" : "Stopped")
                            .foregroundStyle(.secondary)
                    }
                }

                if isEnabled != isRunning {
                    Section {
                        Label("Restart the app to apply changes", systemImage: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }

                Section("Launch Argument") {
                    Text("Pass `--debug-server` to enable without the toggle.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Debug")
        }
    }

#endif
