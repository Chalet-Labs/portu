import PortuCore
import SwiftUI

enum APIKeyInputMode: Equatable {
    case visibleText
    case secureText
}

private enum APIKeyFieldID: Hashable {
    case zapper
    case debank
    case coingecko
}

private struct APIKeyFieldDescriptor {
    let id: APIKeyFieldID
    let title: String
    let glyph: String
    let foreground: Color
    let background: Color
    let hint: String?
}

private extension APIKeyFieldDescriptor {
    static let zapper = Self(
        id: .zapper,
        title: "Zapper",
        glyph: "Z",
        foreground: SettingsDesign.accentBlue,
        background: SettingsDesign.blueGlyphBackground,
        hint: nil)

    static let debank = Self(
        id: .debank,
        title: "DeBank",
        glyph: "D",
        foreground: SettingsDesign.warningOrange,
        background: SettingsDesign.orangeGlyphBackground,
        hint: nil)

    static let coingecko = Self(
        id: .coingecko,
        title: "CoinGecko",
        glyph: "C",
        foreground: Color(red: 0.015, green: 0.520, blue: 0.275),
        background: Color(red: 0.885, green: 0.985, blue: 0.930),
        hint: "Optional. Provides higher rate limits.")
}

enum APIKeysSettingsLayout {
    static let defaultInputMode: APIKeyInputMode = .secureText

    static func inputMode(isVisible: Bool) -> APIKeyInputMode {
        isVisible ? .visibleText : defaultInputMode
    }
}

struct APIKeysSettingsTab: View {
    @State private var viewModel = APIKeysViewModel()
    @State private var newRPCChain: Chain = .ethereum
    @State private var newRPCURL = ""
    @State private var visibleAPIKeyFields: Set<APIKeyFieldID> = []
    @State private var hasPendingSave = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        SettingsPage(tab: .apiKeys, badge: .autoSave) {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSectionCard(
                    title: "Provider API Keys",
                    subtitle: "Secrets are stored locally in macOS Keychain.") {
                        VStack(spacing: 0) {
                            apiKeyField(
                                .zapper,
                                text: $viewModel.zapperAPIKey)

                            SettingsDivider()
                                .padding(.vertical, 8)

                            apiKeyField(
                                .debank,
                                text: $viewModel.debankAPIKey)

                            SettingsDivider()
                                .padding(.vertical, 8)

                            apiKeyField(
                                .coingecko,
                                text: $viewModel.coingeckoAPIKey)
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
        .onDisappear { flushPendingSave() }
    }

    private func apiKeyField(
        _ descriptor: APIKeyFieldDescriptor,
        text: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsLetterTile(
                glyph: descriptor.glyph,
                foreground: descriptor.foreground,
                background: descriptor.background)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(descriptor.title)
                    .font(.system(size: SettingsMetrics.rowTitleSize, weight: .bold))
                    .foregroundStyle(SettingsDesign.primaryText)

                if let hint = descriptor.hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(SettingsDesign.secondaryText)
                }
            }
            .frame(width: 190, alignment: .leading)

            let isVisible = visibleAPIKeyFields.contains(descriptor.id)

            HStack(spacing: 8) {
                apiKeyInput(
                    text: text,
                    mode: APIKeysSettingsLayout.inputMode(isVisible: isVisible))
                    .textFieldStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(SettingsDesign.primaryText)
                    .frame(maxWidth: .infinity)

                Button {
                    toggleVisibility(for: descriptor.id)
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SettingsDesign.secondaryText)
                .frame(width: 28, height: 28)
                .accessibilityLabel(isVisible ? "Hide \(descriptor.title) API key" : "Show \(descriptor.title) API key")
            }
            .settingsInputFrame(height: SettingsMetrics.compactInputHeight)
        }
    }

    @ViewBuilder
    private func apiKeyInput(text: Binding<String>, mode: APIKeyInputMode) -> some View {
        switch mode {
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

    private func toggleVisibility(for field: APIKeyFieldID) {
        if visibleAPIKeyFields.contains(field) {
            visibleAPIKeyFields.remove(field)
        } else {
            visibleAPIKeyFields.insert(field)
        }
    }

    private func debounceSave() {
        guard !viewModel.isLoading else { return }
        hasPendingSave = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            viewModel.save()
            hasPendingSave = false
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        guard hasPendingSave, !viewModel.isLoading else { return }
        viewModel.save()
        hasPendingSave = false
    }
}
