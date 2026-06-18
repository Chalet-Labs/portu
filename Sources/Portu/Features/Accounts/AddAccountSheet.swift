import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let mode: AccountSheetMode
    private let account: Account?
    private let isSyncing: Bool
    private let canSync: Bool
    private let isSyncBlocked: Bool
    private let onSync: ((UUID) -> Void)?
    private let secretStore: any SecretStore

    @State private var draft: AccountSheetDraft
    @State private var saveError: String?

    init(
        mode: AccountSheetMode = .add,
        account: Account? = nil,
        isSyncing: Bool = false,
        canSync: Bool = false,
        isSyncBlocked: Bool = false,
        onSync: ((UUID) -> Void)? = nil,
        secretStore: any SecretStore = LocalSecretStore()) {
        self.mode = mode
        self.account = account
        self.isSyncing = isSyncing
        self.canSync = canSync
        self.isSyncBlocked = isSyncBlocked
        self.onSync = onSync
        self.secretStore = secretStore
        let initialDraft = if mode.isEditing, let account {
            AccountSheetDraft.editing(account: account, secretStore: secretStore)
        } else {
            AccountSheetDraft.adding()
        }
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(PortuTheme.dashboardStroke)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if mode.isEditing {
                        lockedAccountTypeLabel
                    } else {
                        AddAccountTabSelector(selection: $draft.selectedTab)
                    }

                    Group {
                        switch draft.selectedTab {
                        case .chain:
                            chainAccountTab
                        case .manual:
                            manualAccountTab
                        case .exchange:
                            exchangeAccountTab
                        }
                    }
                    .animation(.snappy(duration: 0.18), value: draft.selectedTab)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.automatic)

            footer
        }
        .frame(width: 780, height: 580)
        .background(PortuTheme.dashboardPanelBackground)
        .foregroundStyle(PortuTheme.dashboardText)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .alert(alertTitle, isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(mode.isEditing ? "Edit account" : "Add new account")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(PortuTheme.dashboardText)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AddAccountAccessibility.closeButtonLabel)
            .accessibilityHint("Closes the add account sheet.")
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
    }

    private var lockedAccountTypeLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PortuTheme.dashboardSecondaryText)

            Text(draft.selectedTab.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PortuTheme.dashboardText)

            Spacer(minLength: 8)

            Text("Type locked while editing")
                .font(.system(size: 12))
                .foregroundStyle(PortuTheme.dashboardTertiaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PortuTheme.dashboardPanelElevatedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }

    private var alertTitle: String {
        mode.isEditing ? "Unable to Save Account" : "Unable to Add Account"
    }

    // MARK: - Chain Account Tab

    private var chainAccountTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddAccountSupportPanel(
                title: "CHAINS WE SUPPORT:",
                chips: [
                    .init(title: "Ethereum & L2s", systemImage: "diamond.fill", tint: .purple),
                    .init(title: "Solana", systemImage: "circle.hexagongrid.fill", tint: .green),
                    .init(title: "Bitcoin", systemImage: "bitcoinsign.circle.fill", tint: .orange),
                    .init(title: "Base", systemImage: "b.circle.fill", tint: .blue),
                    .init(title: "Polygon", systemImage: "hexagon.fill", tint: .purple),
                    .init(title: "+ 6 more...", systemImage: nil, tint: PortuTheme.dashboardSecondaryText)
                ],
                searchPlaceholder: "Search chain to test support",
                linkTitle: "See full list")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    AddAccountTextField(
                        title: "Account Address",
                        placeholder: "Paste wallet address",
                        text: $draft.chainAddress,
                        isRequired: true,
                        isMonospaced: true)

                    chainTypePicker
                }

                AddAccountTextField(
                    title: "Account Name",
                    placeholder: "Account Name",
                    text: $draft.chainName,
                    isRequired: true)

                HStack(alignment: .top, spacing: 10) {
                    AddAccountTextField(
                        title: "Description",
                        placeholder: "Descriptive text",
                        text: $draft.chainNotes)

                    AddAccountTextField(
                        title: "Account group",
                        placeholder: "Select a group",
                        text: $draft.chainGroup)
                }

                InlineSourceNote(text: "Data source: Zapper API")
            }
        }
    }

    private var chainTypePicker: some View {
        AddAccountMenuField(
            title: "Account Type",
            value: draft.isEVM ? "Ethereum & L2s (EVM)" : draft.specificChain.addAccountTitle,
            isRequired: true) {
                Button("Ethereum & L2s (EVM)") {
                    draft.isEVM = true
                }

                Divider()

                ForEach([Chain.solana, .bitcoin], id: \.self) { chain in
                    Button(chain.addAccountTitle) {
                        draft.specificChain = chain
                        draft.isEVM = false
                    }
                }
            }
    }

    // MARK: - Manual Account Tab

    private var manualAccountTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddAccountManualInfoPanel()

            VStack(alignment: .leading, spacing: 10) {
                AddAccountTextField(
                    title: "Account Name",
                    placeholder: "Account Name",
                    text: $draft.manualName,
                    isRequired: true)

                HStack(alignment: .top, spacing: 10) {
                    AddAccountTextField(
                        title: "Description",
                        placeholder: "Descriptive text",
                        text: $draft.manualNotes)

                    AddAccountTextField(
                        title: "Account group",
                        placeholder: "Select a group",
                        text: $draft.manualGroup)
                }
            }
        }
    }

    // MARK: - Exchange Account Tab

    private var exchangeAccountTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddAccountSupportPanel(
                title: "EXCHANGES WE SUPPORT:",
                chips: [
                    .init(title: "Kraken", systemImage: "k.circle.fill", tint: .purple),
                    .init(title: "Coinbase", systemImage: "c.circle.fill", tint: .blue),
                    .init(title: "Binance", systemImage: "diamond.circle.fill", tint: .yellow)
                ],
                searchPlaceholder: nil,
                linkTitle: "See full list")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    exchangePicker

                    AddAccountTextField(
                        title: "Name",
                        placeholder: "Account Name",
                        text: $draft.exchangeName,
                        isRequired: true)
                }

                AddAccountKeepInMindPanel()

                HStack(alignment: .top, spacing: 10) {
                    AddAccountSecureField(
                        title: "API Key",
                        placeholder: "API Key",
                        text: $draft.exchangeAPIKey,
                        isRequired: true)

                    AddAccountSecureField(
                        title: "Private Key",
                        placeholder: "Private Key",
                        text: $draft.exchangeAPISecret,
                        isRequired: true)
                }

                if draft.exchangeType == .coinbase {
                    AddAccountSecureField(
                        title: "Passphrase",
                        placeholder: "Passphrase",
                        text: $draft.exchangePassphrase)
                }

                HStack(alignment: .top, spacing: 10) {
                    AddAccountTextField(
                        title: "Description",
                        placeholder: "Descriptive text",
                        text: $draft.exchangeNotes)

                    AddAccountTextField(
                        title: "Account group",
                        placeholder: "Select a group",
                        text: $draft.exchangeGroup)
                }
            }
        }
    }

    private var exchangePicker: some View {
        AddAccountMenuField(
            title: "Exchange",
            value: draft.exchangeType.addAccountTitle,
            isRequired: true) {
                ForEach(ExchangeType.allCases, id: \.self) { type in
                    Button(type.addAccountTitle) {
                        draft.exchangeType = type
                        draft.exchangePassphrase = AddAccountExchangeSecrets.passphraseAfterSelecting(
                            type,
                            currentPassphrase: draft.exchangePassphrase)
                    }
                }
            }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(PortuTheme.dashboardStroke)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PortuTheme.dashboardText)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(PortuTheme.dashboardMutedPanelBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Spacer()

                if let accountID = mode.editedAccountID {
                    Button {
                        onSync?(accountID)
                    } label: {
                        HStack(spacing: 7) {
                            Text("Sync")
                            if isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.62)
                                    .frame(width: 12, height: 12)
                                    .tint(PortuTheme.dashboardGold)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .bold))
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(syncButtonEnabled ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(PortuTheme.dashboardMutedPanelBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!syncButtonEnabled)
                    .help(syncHelpText)
                }

                Button {
                    saveAccount()
                } label: {
                    Text(mode.isEditing ? "Save Changes" : "Add Account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(canSave ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(canSave ? PortuTheme.dashboardGoldMuted : PortuTheme.dashboardMutedPanelBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(canSave ? PortuTheme.dashboardMutedStroke : PortuTheme.dashboardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(PortuTheme.dashboardPanelBackground)
        }
    }

    // MARK: - Save

    private var canSave: Bool {
        draft.canSave
    }

    private var syncButtonEnabled: Bool {
        canSync && !isSyncing && !isSyncBlocked
    }

    private var syncHelpText: String {
        if isSyncing || isSyncBlocked {
            return "Another sync is already running."
        }
        if canSync == false {
            return "This account cannot be synced."
        }
        return "Sync this account."
    }

    private func saveAccount() {
        do {
            try AccountSheetSaveCoordinator.save(
                draft: draft,
                mode: mode,
                editing: account,
                modelContext: modelContext,
                secretStore: secretStore)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

enum AddAccountAccessibility {
    static let closeButtonLabel = "Close"
}

enum AddAccountExchangeSecrets {
    static func persistedPassphrase(_ passphrase: String, for exchangeType: ExchangeType) -> String? {
        guard exchangeType == .coinbase, !passphrase.isEmpty else {
            return nil
        }

        return passphrase
    }

    static func passphraseAfterSelecting(
        _ exchangeType: ExchangeType,
        currentPassphrase: String) -> String {
        exchangeType == .coinbase ? currentPassphrase : ""
    }
}
