import PortuCore
import SwiftUI

enum APIKeyInputMode: Equatable {
    case visibleText
    case secureText
}

enum APIKeysSettingsLayout {
    static let inputMode: APIKeyInputMode = .visibleText
}

struct APIKeysSettingsTab: View {
    @State private var viewModel = APIKeysViewModel()
    @State private var newRPCChain: Chain = .ethereum
    @State private var newRPCURL = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        SettingsPage(tab: .apiKeys, badge: .autoSave) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSectionCard(
                    title: "Provider API Keys",
                    subtitle: "Secrets are stored locally in macOS Keychain.") {
                        VStack(spacing: 0) {
                            apiKeyField(
                                title: "Zapper",
                                glyph: "Z",
                                foreground: SettingsDesign.accentBlue,
                                background: SettingsDesign.blueGlyphBackground,
                                text: $viewModel.zapperAPIKey)

                            SettingsDivider()
                                .padding(.vertical, 8)

                            apiKeyField(
                                title: "DeBank",
                                glyph: "D",
                                foreground: SettingsDesign.warningOrange,
                                background: SettingsDesign.orangeGlyphBackground,
                                text: $viewModel.debankAPIKey)

                            SettingsDivider()
                                .padding(.vertical, 8)

                            apiKeyField(
                                title: "CoinGecko",
                                glyph: "C",
                                foreground: Color(red: 0.015, green: 0.520, blue: 0.275),
                                background: Color(red: 0.885, green: 0.985, blue: 0.930),
                                text: $viewModel.coingeckoAPIKey,
                                hint: "Optional. Provides higher rate limits.")
                        }
                    }

                SettingsSectionCard(
                    title: "Custom RPCs",
                    subtitle: "Override a chain's default RPC endpoint when needed.") {
                        VStack(alignment: .leading, spacing: 22) {
                            rpcTable
                            addEndpointSection

                            if let keychainError = viewModel.keychainError {
                                SettingsInlineNotice(
                                    title: "Keychain Error",
                                    message: keychainError,
                                    style: .error)
                            }
                        }
                    }
            }
        }
        .task { if !viewModel.hasLoaded { viewModel.load() } }
        .onChange(of: viewModel.zapperAPIKey) { _, _ in debounceSave() }
        .onChange(of: viewModel.debankAPIKey) { _, _ in debounceSave() }
        .onChange(of: viewModel.coingeckoAPIKey) { _, _ in debounceSave() }
    }

    private func apiKeyField(
        title: String,
        glyph: String,
        foreground: Color,
        background: Color,
        text: Binding<String>,
        hint: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsLetterTile(
                glyph: glyph,
                foreground: foreground,
                background: background)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)

                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
            }
            .frame(width: 190, alignment: .leading)

            apiKeyInput(text: text)
                .textFieldStyle(.plain)
                .font(.footnote)
                .foregroundStyle(SettingsDesign.primaryText)
                .settingsInputFrame(height: SettingsMetrics.compactInputHeight)
        }
    }

    @ViewBuilder
    private func apiKeyInput(text: Binding<String>) -> some View {
        switch APIKeysSettingsLayout.inputMode {
        case .visibleText:
            TextField("Enter API key", text: text)
        case .secureText:
            SecureField("Enter API key", text: text)
        }
    }

    private var rpcTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Text("Chain")
                    .frame(width: 132, alignment: .leading)
                Text("RPC URL")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("")
                    .frame(width: 46)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(SettingsDesign.secondaryText)
            .padding(.horizontal, 16)
            .frame(height: 32)

            if viewModel.rpcEndpoints.isEmpty {
                HStack(spacing: 18) {
                    Text("Configured endpoints appear here")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {} label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                    .settingsIconButton(color: SettingsDesign.warningOrange)
                }
                .font(.footnote)
                .foregroundStyle(SettingsDesign.secondaryText)
                .padding(.horizontal, 16)
                .frame(height: 42)
            } else {
                ForEach(
                    viewModel.rpcEndpoints.sorted(by: { $0.key.rawValue < $1.key.rawValue }),
                    id: \.key) { chain, url in
                        HStack(spacing: 18) {
                            Text(chain.rawValue.capitalized)
                                .foregroundStyle(SettingsDesign.primaryText)
                                .frame(width: 132, alignment: .leading)
                            Text(url)
                                .foregroundStyle(SettingsDesign.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                viewModel.removeRPCEndpoint(chain: chain)
                                debounceSave()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .settingsIconButton(color: SettingsDesign.warningOrange)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                    }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SettingsDesign.separator, lineWidth: 1))
    }

    private var addEndpointSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Add endpoint")
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)
                Text("Pick an available chain, enter its RPC URL, then add it.")
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.secondaryText)
            }

            if !availableChains.isEmpty {
                HStack(spacing: 14) {
                    Menu {
                        ForEach(availableChains, id: \.self) { chain in
                            Button(chain.rawValue.capitalized) {
                                newRPCChain = chain
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(newRPCChain.rawValue.capitalized)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.primaryText)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .settingsMenuFrame(height: SettingsMetrics.compactInputHeight)
                    .frame(width: 132)

                    TextField("RPC URL", text: $newRPCURL)
                        .textFieldStyle(.plain)
                        .font(.footnote)
                        .foregroundStyle(SettingsDesign.primaryText)
                        .settingsInputFrame(height: SettingsMetrics.compactInputHeight)

                    Button {
                        guard !newRPCURL.isEmpty else { return }
                        viewModel.addRPCEndpoint(chain: newRPCChain, url: newRPCURL)
                        newRPCURL = ""
                        if let next = availableChains.first {
                            newRPCChain = next
                        }
                        debounceSave()
                    } label: {
                        Text("Add")
                            .font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .settingsPrimaryButton(isDisabled: newRPCURL.isEmpty)
                    .disabled(newRPCURL.isEmpty)
                }
            } else {
                Text("All supported chains have custom endpoints.")
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.secondaryText)
            }
        }
    }

    private var availableChains: [Chain] {
        Chain.allCases.filter { viewModel.rpcEndpoints[$0] == nil }
    }

    private func debounceSave() {
        guard !viewModel.isLoading else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            viewModel.save()
        }
    }
}

struct SettingsInlineNotice: View {
    enum Style {
        case error
        case action
    }

    let title: String
    let message: String?
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: message == nil ? 0 : 6) {
            Text(title)
                .font(.footnote.weight(.bold))
            if let message {
                Text(message)
                    .font(.footnote)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: message == nil ? 38 : 56, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(stroke, lineWidth: 1))
    }

    private var background: Color {
        switch style {
        case .error: Color(red: 1.0, green: 0.970, blue: 0.925)
        case .action: Color(red: 0.910, green: 0.930, blue: 1.0)
        }
    }

    private var stroke: Color {
        switch style {
        case .error: Color(red: 0.980, green: 0.590, blue: 0.235)
        case .action: Color(red: 0.600, green: 0.690, blue: 1.0)
        }
    }

    private var foreground: Color {
        switch style {
        case .error: Color(red: 0.640, green: 0.160, blue: 0.050)
        case .action: Color(red: 0.245, green: 0.180, blue: 0.780)
        }
    }
}

extension View {
    func settingsInputFrame(height: CGFloat) -> some View {
        padding(.horizontal, 12)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsDesign.subtleCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }

    func settingsMenuFrame(height: CGFloat) -> some View {
        padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsDesign.subtleCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SettingsDesign.cardStroke, lineWidth: 1))
    }

    func settingsIconButton(color: Color) -> some View {
        foregroundStyle(color)
            .frame(width: 42, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.10)))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(color.opacity(0.25), lineWidth: 1))
    }

    func settingsPrimaryButton(isDisabled: Bool) -> some View {
        foregroundStyle(isDisabled ? SettingsDesign.secondaryText : Color.white)
            .frame(width: 64, height: SettingsMetrics.compactControlHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDisabled ? Color(red: 0.800, green: 0.830, blue: 0.880) : SettingsDesign.accentBlue))
    }
}
