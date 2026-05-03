#if DEBUG

    import SwiftUI

    struct DebugSettingsTab: View {
        @Environment(AppState.self) private var appState
        @AppStorage(DebugMode.enabledKey) private var isEnabled = false
        @AppStorage(DebugMode.portKey) private var port = Int(DebugMode.defaultPort)

        private var isRunning: Bool {
            appState.debugServer != nil
        }

        private var launchArgActive: Bool {
            ProcessInfo.processInfo.arguments.contains(DebugMode.launchArgument)
        }

        private var needsRestart: Bool {
            if launchArgActive {
                if isRunning, let serverPort = appState.debugServer?.port, port != Int(serverPort) { return true }
                return false
            }
            if isEnabled != isRunning { return true }
            if isRunning, let serverPort = appState.debugServer?.port, port != Int(serverPort) { return true }
            return false
        }

        var body: some View {
            SettingsPage(tab: .debug, badge: .debugOnly) {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsSectionCard(
                        title: "Debug Server",
                        subtitle: "Enable, configure, and inspect the local debug server.") {
                            VStack(spacing: 0) {
                                debugToggleRow

                                SettingsDivider()
                                    .padding(.vertical, 14)

                                portRow

                                SettingsDivider()
                                    .padding(.vertical, 14)

                                statusRow
                            }
                        }

                    SettingsSectionCard(
                        title: "Conditional Notices",
                        subtitle: "Shown only when the matching debug state is active.") {
                            VStack(alignment: .leading, spacing: 12) {
                                if launchArgActive, isRunning {
                                    SettingsInlineNotice(
                                        title: "Enabled via \(DebugMode.launchArgument) launch argument",
                                        message: nil,
                                        style: .action)
                                }

                                if needsRestart {
                                    SettingsInlineNotice(
                                        title: "Restart the app to apply changes",
                                        message: nil,
                                        style: .action)
                                }

                                if appState.debugServerStartFailed, isEnabled || launchArgActive {
                                    SettingsInlineNotice(
                                        title: "Server failed to start",
                                        message: "Check Console for details.",
                                        style: .error)
                                }

                                if !launchArgActive, !needsRestart, !appState.debugServerStartFailed {
                                    Text("No active debug notices.")
                                        .font(.callout)
                                        .foregroundStyle(SettingsDesign.secondaryText)
                                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                                }
                            }
                        }

                    SettingsSectionCard(
                        title: "Launch Argument",
                        subtitle: "Enable the server without using the toggle.") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(DebugMode.launchArgument)
                                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color(red: 0.040, green: 0.060, blue: 0.100)))

                                Text("When active and running, Portu shows that the debug server was enabled via launch argument.")
                                    .font(.footnote)
                                    .foregroundStyle(SettingsDesign.secondaryText)
                            }
                        }
                }
            }
        }

        private var debugToggleRow: some View {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enable Debug Server")
                        .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                        .foregroundStyle(SettingsDesign.primaryText)
                    Text("Toggles the local debug server preference.")
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                Spacer(minLength: 18)

                Toggle("Enable Debug Server", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }

        private var portRow: some View {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Port")
                        .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                        .foregroundStyle(SettingsDesign.primaryText)
                    Text("Default port: \(DebugMode.defaultPort)")
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }

                Spacer(minLength: 18)

                TextField("Port", value: $port, format: .number)
                    .textFieldStyle(.plain)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SettingsDesign.primaryText)
                    .multilineTextAlignment(.trailing)
                    .settingsInputFrame(height: SettingsMetrics.compactInputHeight)
                    .frame(width: 96)
                    .onChange(of: port) { _, newValue in
                        if newValue <= 0 || newValue > Int(UInt16.max) {
                            port = Int(DebugMode.defaultPort)
                        }
                    }
            }
        }

        private var statusRow: some View {
            HStack(spacing: 12) {
                Text("Status")
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)

                Circle()
                    .fill(isRunning ? Color.green : Color(red: 0.590, green: 0.650, blue: 0.740))
                    .frame(width: 10, height: 10)

                Text(isRunning ? "Running" : "Stopped")
                    .font(.body)
                    .foregroundStyle(SettingsDesign.secondaryText)

                Spacer(minLength: 18)

                if let debugServer = appState.debugServer {
                    Text("Running on port \(debugServer.port)")
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.secondaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(SettingsDesign.subtleCardBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(SettingsDesign.separator, lineWidth: 1))
                }
            }
        }
    }

#endif
