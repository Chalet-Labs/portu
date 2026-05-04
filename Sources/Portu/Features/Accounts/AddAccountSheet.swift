import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: AddAccountTab = .chain

    // Chain account fields
    @State private var chainName = ""
    @State private var chainAddress = ""
    @State private var chainGroup = ""
    @State private var chainNotes = ""
    @State private var isEVM = true
    @State private var specificChain: Chain = .solana

    // Manual account fields
    @State private var manualName = ""
    @State private var manualNotes = ""
    @State private var manualGroup = ""

    // Exchange account fields
    @State private var exchangeName = ""
    @State private var exchangeType: ExchangeType = .kraken
    @State private var exchangeAPIKey = ""
    @State private var exchangeAPISecret = ""
    @State private var exchangePassphrase = ""
    @State private var exchangeGroup = ""
    @State private var exchangeNotes = ""
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(PortuTheme.dashboardStroke)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AddAccountTabSelector(selection: $selectedTab)

                    Group {
                        switch selectedTab {
                        case .chain:
                            chainAccountTab
                        case .manual:
                            manualAccountTab
                        case .exchange:
                            exchangeAccountTab
                        }
                    }
                    .animation(.snappy(duration: 0.18), value: selectedTab)
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
        .alert("Unable to Add Account", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Add new account")
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
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
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
                        text: $chainAddress,
                        isRequired: true,
                        isMonospaced: true)

                    chainTypePicker
                }

                AddAccountTextField(
                    title: "Account Name",
                    placeholder: "Account Name",
                    text: $chainName,
                    isRequired: true)

                HStack(alignment: .top, spacing: 10) {
                    AddAccountTextField(
                        title: "Description",
                        placeholder: "Descriptive text",
                        text: $chainNotes)

                    AddAccountTextField(
                        title: "Account group",
                        placeholder: "Select a group",
                        text: $chainGroup)
                }

                InlineSourceNote(text: "Data source: Zapper API")
            }
        }
    }

    private var chainTypePicker: some View {
        AddAccountMenuField(
            title: "Account Type",
            value: isEVM ? "Ethereum & L2s (EVM)" : specificChain.addAccountTitle,
            isRequired: true) {
                Button("Ethereum & L2s (EVM)") {
                    isEVM = true
                }

                Divider()

                ForEach([Chain.solana, .bitcoin], id: \.self) { chain in
                    Button(chain.addAccountTitle) {
                        specificChain = chain
                        isEVM = false
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
                    text: $manualName,
                    isRequired: true)

                HStack(alignment: .top, spacing: 10) {
                    AddAccountTextField(
                        title: "Description",
                        placeholder: "Descriptive text",
                        text: $manualNotes)

                    AddAccountTextField(
                        title: "Account group",
                        placeholder: "Select a group",
                        text: $manualGroup)
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
                        text: $exchangeName,
                        isRequired: true)
                }

                AddAccountKeepInMindPanel()

                HStack(alignment: .top, spacing: 10) {
                    AddAccountSecureField(
                        title: "API Key",
                        placeholder: "API Key",
                        text: $exchangeAPIKey,
                        isRequired: true)

                    AddAccountSecureField(
                        title: "Private Key",
                        placeholder: "Private Key",
                        text: $exchangeAPISecret,
                        isRequired: true)
                }

                if exchangeType == .coinbase {
                    AddAccountSecureField(
                        title: "Passphrase",
                        placeholder: "Passphrase",
                        text: $exchangePassphrase)
                }

                HStack(alignment: .top, spacing: 10) {
                    AddAccountTextField(
                        title: "Description",
                        placeholder: "Descriptive text",
                        text: $exchangeNotes)

                    AddAccountTextField(
                        title: "Account group",
                        placeholder: "Select a group",
                        text: $exchangeGroup)
                }
            }
        }
    }

    private var exchangePicker: some View {
        AddAccountMenuField(
            title: "Exchange",
            value: exchangeType.addAccountTitle,
            isRequired: true) {
                ForEach(ExchangeType.allCases, id: \.self) { type in
                    Button(type.addAccountTitle) {
                        exchangeType = type
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

                Button {
                    saveAccount()
                } label: {
                    Text("Add Account")
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
        AccountsFeature.canSave(
            tab: selectedTab.rawValue,
            chainName: chainName,
            chainAddress: chainAddress,
            manualName: manualName,
            exchangeName: exchangeName,
            exchangeAPIKey: exchangeAPIKey,
            exchangeAPISecret: exchangeAPISecret)
    }

    private func saveAccount() {
        let didSave: Bool = switch selectedTab {
        case .chain:
            saveChainAccount()
        case .manual:
            saveManualAccount()
        case .exchange:
            saveExchangeAccount()
        }

        if didSave {
            dismiss()
        }
    }

    private func saveChainAccount() -> Bool {
        let account = Account(
            name: chainName,
            kind: .wallet,
            dataSource: .zapper,
            group: chainGroup.isEmpty ? nil : chainGroup,
            notes: chainNotes.isEmpty ? nil : chainNotes)
        let chain: Chain? = isEVM ? nil : specificChain
        let addr = WalletAddress(chain: chain, address: chainAddress, account: account)
        account.addresses = [addr]

        return insertAndSave(account)
    }

    private func saveManualAccount() -> Bool {
        let account = Account(
            name: manualName,
            kind: .manual,
            dataSource: .manual,
            group: manualGroup.isEmpty ? nil : manualGroup,
            notes: manualNotes.isEmpty ? nil : manualNotes)
        return insertAndSave(account)
    }

    private func saveExchangeAccount() -> Bool {
        let accountId = UUID()
        let account = Account(
            id: accountId,
            name: exchangeName,
            kind: .exchange,
            exchangeType: exchangeType,
            dataSource: .exchange,
            group: exchangeGroup.isEmpty ? nil : exchangeGroup,
            notes: exchangeNotes.isEmpty ? nil : exchangeNotes)

        let keychain = KeychainService()
        do {
            try keychain.set(key: .exchangeAPIKey(accountId), value: exchangeAPIKey)
            try keychain.set(key: .exchangeAPISecret(accountId), value: exchangeAPISecret)
            if !exchangePassphrase.isEmpty {
                try keychain.set(key: .exchangePassphrase(accountId), value: exchangePassphrase)
            }
        } catch {
            deleteExchangeCredentials(accountId, keychain: keychain)
            saveError = "Failed to save credentials: \(error.localizedDescription)"
            return false
        }

        if insertAndSave(account) {
            return true
        }

        deleteExchangeCredentials(accountId, keychain: keychain)
        return false
    }

    private func insertAndSave(_ account: Account) -> Bool {
        modelContext.insert(account)
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.delete(account)
            saveError = "Failed to save account: \(error.localizedDescription)"
            return false
        }
    }

    private func deleteExchangeCredentials(_ accountId: UUID, keychain: KeychainService) {
        try? keychain.delete(key: .exchangeAPIKey(accountId))
        try? keychain.delete(key: .exchangeAPISecret(accountId))
        try? keychain.delete(key: .exchangePassphrase(accountId))
    }
}
