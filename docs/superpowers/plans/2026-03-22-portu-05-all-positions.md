# Phase 3: All Positions View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the All Positions view — positions grouped by type and protocol, with a filter sidebar and manual position entry.

**Architecture:** `HSplitView` with main content (grouped list) + filter sidebar. Positions grouped by type (Idle Onchain, Idle Exchanges) then by protocol. Filter sidebar uses `@Query` predicates.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (Views §3)

**Depends on:** Plans 01-03 must be completed first.

---

## File Structure

### Create
- `Sources/Portu/Features/Positions/AllPositionsView.swift`
- `Sources/Portu/Features/Positions/PositionGroupView.swift`
- `Sources/Portu/Features/Positions/PositionFilterSidebar.swift`
- `Sources/Portu/Features/Positions/AddPositionSheet.swift`

---

### Task 1: AllPositionsView with grouped content

**Files:**
- Create: `Sources/Portu/Features/Positions/AllPositionsView.swift`
- Create: `Sources/Portu/Features/Positions/PositionGroupView.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p Sources/Portu/Features/Positions
```

- [ ] **Step 2: Write PositionGroupView**

```swift
// Sources/Portu/Features/Positions/PositionGroupView.swift
import SwiftUI
import PortuCore
import PortuUI

struct PositionGroupView: View {
    let position: Position
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: protocol name, chain, health factor
            HStack {
                if let name = position.protocolName {
                    Text(name).font(.headline)
                } else {
                    Text(position.positionType.rawValue.capitalized).font(.headline)
                }

                if let chain = position.chain {
                    Text(chain.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                Spacer()

                if let hf = position.healthFactor {
                    Label("HF: \(hf, specifier: "%.2f")", systemImage: "heart.text.square")
                        .font(.caption)
                        .foregroundStyle(hf < 1.2 ? .red : hf < 1.5 ? .orange : .green)
                }

                // Net value (signed)
                Text(position.netUSDValue, format: .currency(code: "USD"))
                    .font(.headline)
                    .foregroundStyle(position.netUSDValue < 0 ? .red : .primary)
            }

            // Token rows
            ForEach(position.tokens, id: \.id) { token in
                HStack {
                    // Role prefix
                    if token.role == .supply { Text("→ Supply").font(.caption).foregroundStyle(.green) }
                    else if token.role.isBorrow { Text("← Borrow").font(.caption).foregroundStyle(.orange) }
                    else if token.role.isReward { Text("★ Reward").font(.caption).foregroundStyle(.yellow) }
                    else if token.role == .stake { Text("⊕ Stake").font(.caption).foregroundStyle(.blue) }
                    else { Text("○ Balance").font(.caption).foregroundStyle(.secondary) }

                    Text(token.asset?.symbol ?? "???")
                        .fontWeight(.medium)

                    Spacer()

                    Text(token.amount, format: .number.precision(.fractionLength(2...6)))
                        .foregroundStyle(.secondary)

                    // Always positive display
                    let value = tokenValue(token)
                    Text(value, format: .currency(code: "USD"))
                        .frame(width: 100, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tokenValue(_ token: PositionToken) -> Decimal {
        token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
            ?? token.usdValue
    }
}
```

- [ ] **Step 3: Write AllPositionsView**

```swift
// Sources/Portu/Features/Positions/AllPositionsView.swift
import SwiftUI
import SwiftData
import PortuCore

struct AllPositionsView: View {
    @Query(filter: #Predicate<Position> { $0.account?.isActive == true })
    private var positions: [Position]

    @State private var filterType: PositionType? = nil
    @State private var filterProtocol: String? = nil
    @State private var showAddSheet = false

    private var filteredPositions: [Position] {
        positions.filter { pos in
            if let ft = filterType, pos.positionType != ft { return false }
            if let fp = filterProtocol, pos.protocolId != fp { return false }
            return true
        }
    }

    /// Group positions: first by type, then by protocolId
    private var groupedByType: [(PositionType, [Position])] {
        Dictionary(grouping: filteredPositions, by: \.positionType)
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var body: some View {
        HSplitView {
            // Main content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedByType, id: \.0) { (type, positions) in
                        Section {
                            ForEach(positions, id: \.id) { pos in
                                PositionGroupView(position: pos)
                            }
                        } header: {
                            HStack {
                                Text(typeSectionTitle(type))
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                let total = positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
                                Text(total, format: .currency(code: "USD"))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 500)
            .toolbar {
                ToolbarItem {
                    Button("Add Position", systemImage: "plus") {
                        showAddSheet = true
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddPositionSheet()
            }

            // Filter sidebar
            PositionFilterSidebar(
                positions: positions,
                selectedType: $filterType,
                selectedProtocol: $filterProtocol
            )
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
        }
        .navigationTitle("All Positions")
    }

    private func typeSectionTitle(_ type: PositionType) -> String {
        switch type {
        case .idle: "Idle"
        case .lending: "Lending"
        case .liquidityPool: "Liquidity Pools"
        case .staking: "Staking"
        case .farming: "Farming"
        case .vesting: "Vesting"
        case .other: "Other"
        }
    }
}
```

- [ ] **Step 4: Wire into ContentView**

```swift
case .allPositions:
    AllPositionsView()
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/Features/Positions/ Sources/Portu/App/ContentView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add AllPositionsView with grouped positions and token rows

Positions grouped by type then protocol. Token rows show role prefix
and always-positive values per sign convention.
EOF
)"
```

---

### Task 2: Position filter sidebar

**Files:**
- Create: `Sources/Portu/Features/Positions/PositionFilterSidebar.swift`

- [ ] **Step 1: Write PositionFilterSidebar**

```swift
// Sources/Portu/Features/Positions/PositionFilterSidebar.swift
import SwiftUI
import PortuCore

struct PositionFilterSidebar: View {
    let positions: [Position]
    @Binding var selectedType: PositionType?
    @Binding var selectedProtocol: String?

    private var typeFilters: [(PositionType?, String, Decimal)] {
        var result: [(PositionType?, String, Decimal)] = [
            (nil, "All", positions.reduce(Decimal.zero) { $0 + $1.netUSDValue })
        ]
        for type in PositionType.allCases {
            let matching = positions.filter { $0.positionType == type }
            guard !matching.isEmpty else { continue }
            let total = matching.reduce(Decimal.zero) { $0 + $1.netUSDValue }
            result.append((type, type.rawValue.capitalized, total))
        }
        return result
    }

    private var protocolFilters: [(id: String, name: String, value: Decimal)] {
        var byProtocol: [String: (name: String, value: Decimal)] = [:]
        for pos in positions {
            let id = pos.protocolId ?? "__none__"
            let name = pos.protocolName ?? "Wallet"
            var entry = byProtocol[id] ?? (name, 0)
            entry.value += pos.netUSDValue
            byProtocol[id] = entry
        }
        return byProtocol.map { (id: $0.key, name: $0.value.name, value: $0.value.value) }
            .sorted { $0.value > $1.value }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter")
                    .font(.headline)

                // Type filter
                Section("Position Type") {
                    ForEach(typeFilters, id: \.1) { (type, label, total) in
                        Button {
                            selectedType = type
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundStyle(selectedType == type ? .primary : .secondary)
                                Spacer()
                                Text(total, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Protocol filter (uses protocolId to match AllPositionsView filtering)
                Section("Protocol") {
                    Button {
                        selectedProtocol = nil
                    } label: {
                        Text("All Protocols")
                            .foregroundStyle(selectedProtocol == nil ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)

                    ForEach(protocolFilters, id: \.id) { filter in
                        Button {
                            selectedProtocol = filter.id == "__none__" ? nil : filter.id
                        } label: {
                            HStack {
                                Text(filter.name)
                                    .foregroundStyle(selectedProtocol == filter.id ? .primary : .secondary)
                                Spacer()
                                Text(filter.value, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Positions/PositionFilterSidebar.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add position filter sidebar with type and protocol filters
EOF
)"
```

---

### Task 3: Add Position sheet (manual entry)

**Files:**
- Create: `Sources/Portu/Features/Positions/AddPositionSheet.swift`

For manual accounts only. Form: Asset (search/select), Amount, Position Type, optional Protocol, optional USD value override.

- [ ] **Step 1: Write AddPositionSheet**

```swift
// Sources/Portu/Features/Positions/AddPositionSheet.swift
import SwiftUI
import SwiftData
import PortuCore

struct AddPositionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Account> { $0.isActive == true && $0.dataSource == .manual })
    private var manualAccounts: [Account]
    @Query private var assets: [Asset]

    @State private var selectedAccountId: UUID?
    @State private var assetSearch = ""
    @State private var selectedAsset: Asset?
    @State private var amount: Decimal = 0
    @State private var positionType: PositionType = .idle
    @State private var protocolName = ""
    @State private var usdValueOverride: Decimal?

    // New asset fields
    @State private var newSymbol = ""
    @State private var newName = ""
    @State private var newCategory: AssetCategory = .other
    @State private var createNewAsset = false

    private var filteredAssets: [Asset] {
        if assetSearch.isEmpty { return Array(assets.prefix(20)) }
        return assets.filter {
            $0.symbol.localizedCaseInsensitiveContains(assetSearch) ||
            $0.name.localizedCaseInsensitiveContains(assetSearch)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Manual Position")
                .font(.headline)
                .padding()

            Form {
                // Account picker
                Picker("Account", selection: $selectedAccountId) {
                    Text("Select account...").tag(nil as UUID?)
                    ForEach(manualAccounts, id: \.id) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }

                // Asset selection
                Section("Asset") {
                    if createNewAsset {
                        TextField("Symbol", text: $newSymbol)
                        TextField("Name", text: $newName)
                        Picker("Category", selection: $newCategory) {
                            ForEach(AssetCategory.allCases, id: \.self) { cat in
                                Text(cat.rawValue.capitalized).tag(cat)
                            }
                        }
                        Button("Use existing asset") { createNewAsset = false }
                    } else {
                        TextField("Search assets...", text: $assetSearch)
                        List(filteredAssets, id: \.id, selection: $selectedAsset) { asset in
                            HStack {
                                Text(asset.symbol).fontWeight(.medium)
                                Text(asset.name).foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 120)
                        Button("Create new asset") { createNewAsset = true }
                    }
                }

                // Position details
                Section("Details") {
                    TextField("Amount", value: $amount, format: .number)
                    Picker("Type", selection: $positionType) {
                        ForEach(PositionType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    TextField("Protocol (optional)", text: $protocolName)
                    TextField("USD Value (optional override)", value: $usdValueOverride, format: .currency(code: "USD"))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { savePosition() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedAccountId == nil || amount == 0 ||
                              (selectedAsset == nil && !createNewAsset))
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private func savePosition() {
        guard let accountId = selectedAccountId,
              let account = manualAccounts.first(where: { $0.id == accountId }) else { return }

        let asset: Asset
        if createNewAsset {
            asset = Asset(symbol: newSymbol, name: newName, category: newCategory)
            modelContext.insert(asset)
        } else if let existing = selectedAsset {
            asset = existing
        } else {
            return
        }

        let usdValue = usdValueOverride ?? 0
        let token = PositionToken(role: .balance, amount: amount, usdValue: usdValue, asset: asset)
        let position = Position(
            positionType: positionType,
            protocolName: protocolName.isEmpty ? nil : protocolName,
            netUSDValue: usdValue,
            tokens: [token],
            account: account,
            syncedAt: .now
        )
        modelContext.insert(position)
        try? modelContext.save()

        dismiss()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Positions/AddPositionSheet.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add manual position entry sheet

Supports asset search/select or create new. Form fields for amount,
type, protocol, and optional USD value override.
EOF
)"
```

---

### Task 4: Build and verify

- [ ] **Step 1: Build**

Run: `just build 2>&1 | tail -10`

- [ ] **Step 2: Commit any fixes**
