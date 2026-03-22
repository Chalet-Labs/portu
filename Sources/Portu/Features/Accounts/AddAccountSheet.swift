// Sources/Portu/Features/Accounts/AddAccountSheet.swift
import SwiftUI
import SwiftData
import PortuCore

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0

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

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Account")
                .font(.headline)
                .padding()

            TabView(selection: $selectedTab) {
                chainAccountTab.tabItem { Label("Chain", systemImage: "link") }.tag(0)
                manualAccountTab.tabItem { Label("Manual", systemImage: "tray") }.tag(1)
                exchangeAccountTab.tabItem { Label("Exchange", systemImage: "building.columns") }.tag(2)
            }
            .frame(height: 350)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { saveAccount() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 500, height: 480)
    }

    // MARK: - Chain Account Tab

    private var chainAccountTab: some View {
        Form {
            TextField("Name", text: $chainName)
            TextField("Wallet Address", text: $chainAddress)
                .font(.system(.body, design: .monospaced))

            Picker("Chain Type", selection: $isEVM) {
                Text("Ethereum & L2s (EVM)").tag(true)
                Text("Specific Chain").tag(false)
            }

            if !isEVM {
                Picker("Chain", selection: $specificChain) {
                    Text("Solana").tag(Chain.solana)
                    Text("Bitcoin").tag(Chain.bitcoin)
                }
            }

            TextField("Group (optional)", text: $chainGroup)
            TextField("Notes (optional)", text: $chainNotes)

            Text("Data source: Zapper API")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: - Manual Account Tab

    private var manualAccountTab: some View {
        Form {
            TextField("Name", text: $manualName)
            TextField("Group (optional)", text: $manualGroup)
            TextField("Notes (optional)", text: $manualNotes)

            Text("Add positions manually after creating the account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // MARK: - Exchange Account Tab

    private var exchangeAccountTab: some View {
        Form {
            TextField("Account Name", text: $exchangeName)
            Picker("Exchange", selection: $exchangeType) {
                ForEach(ExchangeType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            SecureField("API Key", text: $exchangeAPIKey)
            SecureField("API Secret", text: $exchangeAPISecret)
            if exchangeType == .coinbase {
                SecureField("Passphrase", text: $exchangePassphrase)
            }

            TextField("Group (optional)", text: $exchangeGroup)

            Text("Use read-only API keys for security.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .formStyle(.grouped)
    }

    // MARK: - Save

    private var canSave: Bool {
        switch selectedTab {
        case 0: !chainName.isEmpty && !chainAddress.isEmpty
        case 1: !manualName.isEmpty
        case 2: !exchangeName.isEmpty && !exchangeAPIKey.isEmpty && !exchangeAPISecret.isEmpty
        default: false
        }
    }

    private func saveAccount() {
        switch selectedTab {
        case 0: saveChainAccount()
        case 1: saveManualAccount()
        case 2: saveExchangeAccount()
        default: break
        }
        dismiss()
    }

    private func saveChainAccount() {
        let account = Account(
            name: chainName,
            kind: .wallet,
            dataSource: .zapper,
            group: chainGroup.isEmpty ? nil : chainGroup,
            notes: chainNotes.isEmpty ? nil : chainNotes
        )
        let chain: Chain? = isEVM ? nil : specificChain
        let addr = WalletAddress(chain: chain, address: chainAddress, account: account)
        account.addresses = [addr]

        modelContext.insert(account)
        try? modelContext.save()
    }

    private func saveManualAccount() {
        let account = Account(
            name: manualName,
            kind: .manual,
            dataSource: .manual,
            group: manualGroup.isEmpty ? nil : manualGroup,
            notes: manualNotes.isEmpty ? nil : manualNotes
        )
        modelContext.insert(account)
        try? modelContext.save()
    }

    private func saveExchangeAccount() {
        let account = Account(
            name: exchangeName,
            kind: .exchange,
            exchangeType: exchangeType,
            dataSource: .exchange,
            group: exchangeGroup.isEmpty ? nil : exchangeGroup
        )
        modelContext.insert(account)
        try? modelContext.save()

        // Store credentials in Keychain
        let keychain = KeychainService()
        let prefix = "portu.exchange.\(account.id.uuidString)"
        try? keychain.set(key: "\(prefix).apiKey", value: exchangeAPIKey)
        try? keychain.set(key: "\(prefix).apiSecret", value: exchangeAPISecret)
        if !exchangePassphrase.isEmpty {
            try? keychain.set(key: "\(prefix).passphrase", value: exchangePassphrase)
        }
    }
}
