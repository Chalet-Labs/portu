# Portu Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Accounts workspace with searchable account management, add-account flows for chain/manual/exchange accounts, and secure credential persistence.

**Architecture:** Use one top-level account-management feature with subviews for each creation flow, keep Keychain access behind app-target coordinators rather than inside SwiftUI forms, and let SwiftData drive the list reactively. Treat active/inactive state as a soft-hide toggle instead of delete, and keep exchange credential writes off the main actor by delegating to the Keychain service from a task boundary.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Keychain Services, PortuUI, Swift Testing

**Spec:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

**Skills to use:** @swift-architecture-skill, @swiftui-pro, @swiftdata-pro, @swift-testing-pro, @swift-security-expert

**Dependencies:** Start after `docs/superpowers/plans/2026-03-22-portu-data-foundation.md` and `docs/superpowers/plans/2026-03-22-portu-overview-navigation.md`.

---

## File Map

```
Portu/
├── Sources/Portu/
│   ├── App/ContentView.swift
│   └── Features/
│       └── Accounts/
│           ├── AccountsView.swift                     # new
│           ├── AccountsViewModel.swift                # new
│           ├── AddAccountSheet.swift                  # new
│           ├── AccountSecretsCoordinator.swift        # new
│           ├── Forms/
│           │   ├── ChainAccountForm.swift             # new
│           │   ├── ExchangeAccountForm.swift          # new
│           │   └── ManualAccountForm.swift            # new
│           └── Models/
│               ├── AccountFilter.swift                # new
│               └── AccountRowModel.swift              # new
└── Tests/PortuTests/
    ├── AccountsViewModelTests.swift                   # new
    └── AddAccountSheetTests.swift                     # new
```

---

### Task 1: Build the account list projection, filters, and sorting model

**Files:**
- Create: `Sources/Portu/Features/Accounts/AccountsViewModel.swift`
- Create: `Sources/Portu/Features/Accounts/Models/AccountFilter.swift`
- Create: `Sources/Portu/Features/Accounts/Models/AccountRowModel.swift`
- Test: `Tests/PortuTests/AccountsViewModelTests.swift`

- [ ] **Step 1: Write failing tests for search, group filtering, and balance projection**

```swift
@Test func accountRowsExposeFirstAddressOrExchangeName() throws {
    let row = try #require(AccountsViewModel.fixture().rows.first(where: { $0.name == "Kraken" }))
    #expect(row.secondaryLabel == "Kraken")
}

@Test func inactiveFilterHidesActiveRows() {
    let viewModel = AccountsViewModel.fixture()
    viewModel.filter = .inactive
    #expect(viewModel.visibleRows.allSatisfy { $0.isActive == false })
}
```

- [ ] **Step 2: Run the account view-model tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AccountsViewModelTests test`

Expected: FAIL because the feature-local row models and filters do not exist.

- [ ] **Step 3: Implement the account list projection**

```swift
@MainActor
@Observable
final class AccountsViewModel {
    var searchText = ""
    var filter: AccountFilter = .all
    var selectedGroup: String?
    var rows: [AccountRowModel] = []
}
```

- [ ] **Step 4: Re-run the account view-model tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AccountsViewModelTests test`

Expected: PASS with search, active state, and balance projection covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Accounts/AccountsViewModel.swift Sources/Portu/Features/Accounts/Models Tests/PortuTests/AccountsViewModelTests.swift
git commit -m "feat: add account list projection models"
```

---

### Task 2: Implement the Accounts list workspace and row actions

**Files:**
- Create: `Sources/Portu/Features/Accounts/AccountsView.swift`
- Modify: `Sources/Portu/App/ContentView.swift`
- Modify: `Sources/Portu/Features/Sidebar/SidebarView.swift`

- [ ] **Step 1: Add a failing smoke test for the accounts route**

```swift
@Test func accountsSectionRoutesToAccountsWorkspace() {
    #expect(SidebarSection.allCases.contains(.accounts))
}
```

- [ ] **Step 2: Run the account tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AccountsViewModelTests test`

Expected: FAIL because the feature view and route are missing.

- [ ] **Step 3: Implement the searchable account table**

```swift
struct AccountsView: View {
    var body: some View {
        Table(viewModel.visibleRows) {
            TableColumn("Name", value: \.name)
            TableColumn("Group", value: \.groupName)
            TableColumn("Address", value: \.secondaryLabel)
            TableColumn("Type", value: \.typeLabel)
        }
        .navigationTitle("Accounts")
    }
}
```

- [ ] **Step 4: Re-run the app build**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED with `.accounts` routed to the new feature.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Accounts/AccountsView.swift Sources/Portu/App/ContentView.swift Sources/Portu/Features/Sidebar/SidebarView.swift
git commit -m "feat: add accounts workspace"
```

---

### Task 3: Build the add-account sheet for chain, manual, and exchange flows

**Files:**
- Create: `Sources/Portu/Features/Accounts/AddAccountSheet.swift`
- Create: `Sources/Portu/Features/Accounts/Forms/ChainAccountForm.swift`
- Create: `Sources/Portu/Features/Accounts/Forms/ManualAccountForm.swift`
- Create: `Sources/Portu/Features/Accounts/Forms/ExchangeAccountForm.swift`
- Create: `Sources/Portu/Features/Accounts/AccountSecretsCoordinator.swift`
- Test: `Tests/PortuTests/AddAccountSheetTests.swift`

- [ ] **Step 1: Write failing tests for each add-account path**

```swift
@Test func chainAccountFormCreatesNilChainForEVMAddress() throws {
    let harness = try AddAccountSheetHarness.make()
    try harness.submitChainAccount(name: "Main Wallet", ecosystem: .evm, address: "0xabc")
    #expect(harness.savedAccounts[0].addresses[0].chain == nil)
}

@Test func exchangeAccountFormStoresSecretsViaCoordinator() async throws {
    let coordinator = AccountSecretsCoordinator(secretStore: InMemorySecretStore())
    try await coordinator.saveExchangeSecrets(accountID: UUID(), apiKey: "k", apiSecret: "s", passphrase: "p")
    #expect(await coordinator.hasSecrets)
}
```

- [ ] **Step 2: Run the add-account tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AddAccountSheetTests test`

Expected: FAIL because the sheet, forms, and coordinator are missing.

- [ ] **Step 3: Implement the three-form add-account flow**

```swift
struct AddAccountSheet: View {
    var body: some View {
        TabView {
            ChainAccountForm(...)
                .tabItem { Label("Chain Account", systemImage: "link") }
            ManualAccountForm(...)
                .tabItem { Label("Manual Account", systemImage: "square.and.pencil") }
            ExchangeAccountForm(...)
                .tabItem { Label("Exchange Account", systemImage: "building.columns") }
        }
    }
}
```

- [ ] **Step 4: Re-run the add-account tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AddAccountSheetTests test`

Expected: PASS with persistence and Keychain coordination covered.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Accounts/AddAccountSheet.swift Sources/Portu/Features/Accounts/Forms Sources/Portu/Features/Accounts/AccountSecretsCoordinator.swift Tests/PortuTests/AddAccountSheetTests.swift
git commit -m "feat: add account creation flows"
```

---

### Task 4: Finish active/inactive toggles, disabled bulk import, and end-to-end verification

**Files:**
- Modify: `Sources/Portu/Features/Accounts/AccountsView.swift`
- Modify: `Sources/Portu/Features/Accounts/AccountsViewModel.swift`
- Modify: `Sources/Portu/Features/Accounts/AddAccountSheet.swift`

- [ ] **Step 1: Add a failing test for context-menu active toggling**

```swift
@Test func togglingAccountActiveStatePreservesRowButMovesFilterBucket() throws {
    let viewModel = AccountsViewModel.fixture()
    try viewModel.toggleActiveState(for: "Kraken")
    #expect(viewModel.rows.first(where: { $0.name == "Kraken" })?.isActive == false)
}
```

- [ ] **Step 2: Run the account feature tests**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/AccountsViewModelTests test`

Expected: FAIL because the context-menu action and disabled bulk-import affordance are incomplete.

- [ ] **Step 3: Implement the remaining row actions and placeholders**

```swift
Button("Bulk Import", systemImage: "square.and.arrow.down") {}
    .disabled(true)
    .help("Coming soon")
```

- [ ] **Step 4: Re-run the full app test suite**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' test`

Expected: PASS with account CRUD, secret persistence, and active-state management working together.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Accounts/AccountsView.swift Sources/Portu/Features/Accounts/AccountsViewModel.swift Sources/Portu/Features/Accounts/AddAccountSheet.swift
git commit -m "feat: finish accounts management interactions"
```

