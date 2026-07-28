import PortuCore
import SwiftUI

enum APIKeyInputMode: Equatable {
    case visibleText
    case secureText
}

private enum APIKeyFieldID: Hashable {
    case zerion
    case debank
    case coingecko
}

private struct APIKeyFieldDescriptor {
    let id: APIKeyFieldID
    let title: String
    let systemImage: String
    let foreground: Color
    let background: Color
    let hint: String?
}

private extension APIKeyFieldDescriptor {
    static let zerion = Self(
        id: .zerion,
        title: "Zerion",
        systemImage: SettingsIconography.apiKeyFieldSystemImage,
        foreground: SettingsDesign.accentPrimary,
        background: SettingsDesign.primaryGlyphBackground,
        hint: "Create a personal key at dashboard.zerion.io.")

    static let debank = Self(
        id: .debank,
        title: "DeBank",
        systemImage: SettingsIconography.apiKeyFieldSystemImage,
        foreground: SettingsDesign.warningOrange,
        background: SettingsDesign.orangeGlyphBackground,
        hint: nil)

    static let coingecko = Self(
        id: .coingecko,
        title: "CoinGecko",
        systemImage: SettingsIconography.apiKeyFieldSystemImage,
        foreground: SettingsDesign.successBadgeText,
        background: SettingsDesign.successBadgeBackground,
        hint: "Optional. Provides higher rate limits.")
}

enum APIKeysSettingsLayout {
    static let defaultInputMode: APIKeyInputMode = .secureText

    static func inputMode(isVisible: Bool) -> APIKeyInputMode {
        isVisible ? .visibleText : defaultInputMode
    }
}

struct APIKeysPendingSaveState {
    private(set) var hasPendingSave = false
    private var generation = 0

    mutating func schedule() -> Int {
        generation += 1
        hasPendingSave = true
        return generation
    }

    mutating func complete(_ completedGeneration: Int, succeeded: Bool = true) {
        guard succeeded, completedGeneration == generation else { return }
        hasPendingSave = false
    }

    mutating func generationForFlush() -> Int? {
        guard hasPendingSave else { return nil }
        generation += 1
        return generation
    }
}

enum APIKeysSettingsRetryPolicy {
    static func shouldShow(errorMessage: String?, canSave _: Bool) -> Bool {
        errorMessage != nil
    }

    static func isEnabled(isLoading: Bool) -> Bool {
        !isLoading
    }
}

@MainActor
enum APIKeysSaveTaskCoordinator {
    static func makeTask(
        after previousTask: Task<Void, Never>?,
        delay: Duration?,
        operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            if let delay {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}

struct APIKeysSettingsTab: View {
    @State private var viewModel: APIKeysViewModel
    @State private var newRPCChain: Chain = .ethereum
    @State private var newRPCURL = ""
    @State private var visibleAPIKeyFields: Set<APIKeyFieldID> = []
    @State private var pendingSaveState = APIKeysPendingSaveState()
    @State private var saveTask: Task<Void, Never>?

    init(secretStore: any SecretStore = PortuApp.makeSecretStore()) {
        _viewModel = State(initialValue: APIKeysViewModel(secretStore: secretStore))
    }

    var body: some View {
        SettingsPage(tab: .apiKeys, badge: .autoSave) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionCard(
                    title: "Provider API Keys",
                    subtitle: "Stored securely in Keychain on this Mac.",
                    icon: .apiKeys) {
                        VStack(spacing: 0) {
                            apiKeyField(
                                .zerion,
                                text: $viewModel.zerionAPIKey)

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
                    .disabled(!viewModel.canSave)

                SettingsSectionCard(
                    title: "Custom RPCs",
                    subtitle: "Override a chain's default RPC endpoint when needed.",
                    icon: .customRPCs) {
                        VStack(alignment: .leading, spacing: 22) {
                            rpcTable
                            addEndpointSection
                        }
                    }
                    .disabled(!viewModel.canSave)

                if let secretStoreError = viewModel.secretStoreError {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsInlineNotice(
                            title: "Keychain Error",
                            message: secretStoreError,
                            style: .error)

                        if
                            APIKeysSettingsRetryPolicy.shouldShow(
                                errorMessage: secretStoreError,
                                canSave: viewModel.canSave) {
                            Button("Retry Keychain Access") {
                                if viewModel.canSave {
                                    flushPendingSave()
                                } else {
                                    Task { await viewModel.load() }
                                }
                            }
                            .buttonStyle(.plain)
                            .settingsPrimaryButton(isDisabled: !APIKeysSettingsRetryPolicy.isEnabled(
                                isLoading: viewModel.isLoading))
                            .disabled(!APIKeysSettingsRetryPolicy.isEnabled(isLoading: viewModel.isLoading))
                        }
                    }
                }
            }
        }
        .task { if !viewModel.hasLoaded { await viewModel.load() } }
        .onChange(of: viewModel.zerionAPIKey) { _, _ in debounceSave() }
        .onChange(of: viewModel.debankAPIKey) { _, _ in debounceSave() }
        .onChange(of: viewModel.coingeckoAPIKey) { _, _ in debounceSave() }
        .onDisappear { flushPendingSave() }
    }

    private func apiKeyField(
        _ descriptor: APIKeyFieldDescriptor,
        text: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIconTile(
                systemImage: descriptor.systemImage,
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
                    Image(systemName: SettingsIconography.visibilityToggleActionSystemImage(isCurrentlyVisible: isVisible))
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
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
                .fill(SettingsDesign.subtleCardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.panelCornerRadius, style: .continuous)
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
        guard !viewModel.isLoading, viewModel.canSave else { return }
        let generation = pendingSaveState.schedule()
        let previousTask = saveTask
        previousTask?.cancel()
        saveTask = APIKeysSaveTaskCoordinator.makeTask(
            after: previousTask,
            delay: .seconds(1)) {
                let succeeded = await viewModel.save()
                pendingSaveState.complete(generation, succeeded: succeeded)
            }
    }

    private func flushPendingSave() {
        let previousTask = saveTask
        previousTask?.cancel()
        guard
            !viewModel.isLoading,
            viewModel.canSave,
            let generation = pendingSaveState.generationForFlush()
        else { return }
        saveTask = APIKeysSaveTaskCoordinator.makeTask(after: previousTask, delay: nil) {
            let succeeded = await viewModel.save()
            pendingSaveState.complete(generation, succeeded: succeeded)
        }
    }
}
