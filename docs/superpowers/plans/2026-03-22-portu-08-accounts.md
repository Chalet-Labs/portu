# Phase 3: Accounts View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Accounts management view with CRUD operations and Add Account sheet (3 tabs: Chain, Manual, Exchange).

**Architecture:** SwiftUI `Table` for account list with search/group/status filters. `.sheet` modal for Add Account with `TabView`. Keychain integration for exchange credentials.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (Views §6)

**Depends on:** Plans 01-03 must be completed first.

---

## File Structure

### Create
- `Sources/Portu/Features/Accounts/AccountsView.swift` (replaces old AccountDetailView)
- `Sources/Portu/Features/Accounts/AddAccountSheet.swift`

### Delete
- `Sources/Portu/Features/Accounts/AccountDetailView.swift` — replaced

---

### Task 1: AccountsView with sortable table

**Files:**
- Create: `Sources/Portu/Features/Accounts/AccountsView.swift`

- [ ] **Step 1: Write AccountsView**

```swift
// Sources/Portu/Features/Accounts/AccountsView.swift
import SwiftUI
import SwiftData
import PortuCore

struct AccountsView: View {
    @Query(sort: \Account.name) private var accounts: [Account]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var filterGroup: String? = nil
    @State private var showInactive = false
    @State private var showAddSheet = false
    @State private var sortOrder = [KeyPathComparator(\AccountRowData.name)]

    private struct AccountRowData: Identifiable {
        let id: UUID
        let name: String
        let group: String
        let address: String
        let type: String
        let balance: Decimal
        let isActive: Bool
        let lastSyncError: String?
    }

    private var rows: [AccountRowData] {
        accounts
            .filter { showInactive || $0.isActive }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .filter { filterGroup == nil || $0.group == filterGroup }
            .map { account in
                let balance = account.positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
                let address = account.addresses.first?.address
                    ?? account.exchangeType?.rawValue.capitalized
                    ?? "Manual"

                return AccountRowData(
                    id: account.id,
                    name: account.name,
                    group: account.group ?? "—",
                    address: String(address.prefix(16)) + (address.count > 16 ? "…" : ""),
                    type: account.kind.rawValue.capitalized,
                    balance: balance,
                    isActive: account.isActive,
                    lastSyncError: account.lastSyncError
                )
            }
            .sorted(using: sortOrder)
    }

    private var allGroups: [String] {
        Array(Set(accounts.compactMap(\.group))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search accounts...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 200)

                // Group filter
                Picker("Group", selection: $filterGroup) {
                    Text("All Groups").tag(nil as String?)
                    ForEach(allGroups, id: \.self) { group in
                        Text(group).tag(group as String?)
                    }
                }
                .frame(width: 150)

                // Status filter
                Toggle("Show Inactive", isOn: $showInactive)

                Spacer()

                // Bulk import placeholder
                Button("Bulk Import") {}
                    .disabled(true)
                    .help("Coming soon")

                Button("Add Account", systemImage: "plus") {
                    showAddSheet = true
                }
            }
            .padding()

            // Table
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { row in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(row.isActive ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(row.name)
                            .fontWeight(.medium)
                            .foregroundStyle(row.isActive ? .primary : .secondary)
                    }
                }
                .width(min: 100, ideal: 150)

                TableColumn("Group", value: \.group)
                    .width(min: 60, ideal: 80)

                TableColumn("Address") { row in
                    Text(row.address)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 160)

                TableColumn("Type") { row in
                    Text(row.type)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                .width(min: 60, ideal: 80)

                TableColumn("USD Balance", value: \.balance) { row in
                    VStack(alignment: .trailing) {
                        Text(row.balance, format: .currency(code: "USD"))
                        if let error = row.lastSyncError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }
                .width(min: 80, ideal: 120)
            }
            .contextMenu(forSelectionType: AccountRowData.ID.self) { selection in
                if let id = selection.first, let account = accounts.first(where: { $0.id == id }) {
                    Button(account.isActive ? "Deactivate" : "Activate") {
                        account.isActive.toggle()
                        try? modelContext.save()
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        modelContext.delete(account)
                        try? modelContext.save()
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .sheet(isPresented: $showAddSheet) {
            AddAccountSheet()
        }
    }
}
```

- [ ] **Step 2: Delete old AccountDetailView**

```bash
rm Sources/Portu/Features/Accounts/AccountDetailView.swift
```

- [ ] **Step 3: Wire into ContentView**

```swift
case .accounts:
    AccountsView()
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Features/Accounts/ Sources/Portu/App/ContentView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add AccountsView with sortable table and context menu

Search, group filter, active/inactive toggle. Context menu for
activate/deactivate and delete. Replaces old AccountDetailView.
EOF
)"
```

---

### Task 2: Add Account sheet (3 tabs)

**Files:**
- Create: `Sources/Portu/Features/Accounts/AddAccountSheet.swift`

TabView with Chain Account, Manual Account, Exchange Account tabs.

- [ ] **Step 1: Write AddAccountSheet**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Accounts/AddAccountSheet.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add AddAccountSheet with Chain, Manual, and Exchange tabs

Chain: EVM (all chains) or specific chain with Zapper data source.
Manual: name-only, positions added separately. Exchange: API key/secret
stored in Keychain with read-only permission guidance.
EOF
)"
```

---

### Task 3: Build and verify

- [ ] **Step 1: Build**

Run: `just build 2>&1 | tail -10`

- [ ] **Step 2: Commit any fixes**
