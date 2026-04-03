# Phase 3: Exposure View

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Exposure view — pure computed view showing spot assets, liabilities, and net exposure by category and asset.

**Architecture:** No extra persistence. Computed live from current PositionTokens. Grouped by `AssetCategory`, with toggle between category view and flat asset list.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md` (Views §5)

**Depends on:** Plans 01-03 must be completed first.

---

## File Structure

### Create
- `Sources/Portu/Features/Exposure/ExposureView.swift`

---

### Task 1: ExposureView with summary cards and tables

**Files:**
- Create: `Sources/Portu/Features/Exposure/ExposureView.swift`

**Computation (from spec):**
- Spot Assets = sum(token.usdValue) where role is positive (.supply, .balance, .stake, .lpToken), grouped by category
- Liabilities = sum(token.usdValue) where role is .borrow, grouped by category
- Spot Net = Spot Assets − Liabilities (per category)
- Net Exposure = Spot Net − Stablecoins (excludes stablecoin category)
- Derivatives = future work (placeholder)

- [ ] **Step 1: Create directory**

```bash
mkdir -p Sources/Portu/Features/Exposure
```

- [ ] **Step 2: Write ExposureView**

```swift
// Sources/Portu/Features/Exposure/ExposureView.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct ExposureView: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var allTokens: [PositionToken]

    @State private var showByAsset = false

    // MARK: - Computed Exposure

    private struct CategoryExposure: Identifiable {
        let id: String
        let name: String
        let spotAssets: Decimal
        let liabilities: Decimal
        var spotNet: Decimal { spotAssets - liabilities }
        // Derivatives deferred
        var netExposure: Decimal { spotNet }
    }

    private struct AssetExposure: Identifiable {
        let id: UUID
        let symbol: String
        let category: AssetCategory
        let spotAssets: Decimal
        let liabilities: Decimal
        var spotNet: Decimal { spotAssets - liabilities }
        var netExposure: Decimal { spotNet }
    }

    private var byCategory: [CategoryExposure] {
        var assets: [AssetCategory: Decimal] = [:]
        var borrows: [AssetCategory: Decimal] = [:]

        for token in allTokens {
            let cat = token.asset?.category ?? .other
            let value = tokenUSDValue(token)

            if token.role.isPositive {
                assets[cat, default: 0] += value
            } else if token.role.isBorrow {
                borrows[cat, default: 0] += value
            }
            // reward: excluded
        }

        return AssetCategory.allCases.compactMap { cat in
            let a = assets[cat, default: 0]
            let b = borrows[cat, default: 0]
            guard a > 0 || b > 0 else { return nil }
            return CategoryExposure(
                id: cat.rawValue,
                name: cat.rawValue.capitalized,
                spotAssets: a,
                liabilities: b
            )
        }
    }

    private var byAsset: [AssetExposure] {
        var assetMap: [UUID: (symbol: String, category: AssetCategory, assets: Decimal, borrows: Decimal)] = [:]

        for token in allTokens {
            guard let asset = token.asset else { continue }
            let value = tokenUSDValue(token)

            var entry = assetMap[asset.id] ?? (asset.symbol, asset.category, 0, 0)
            if token.role.isPositive {
                entry.assets += value
            } else if token.role.isBorrow {
                entry.borrows += value
            }
            assetMap[asset.id] = entry
        }

        return assetMap.map { (id, entry) in
            AssetExposure(id: id, symbol: entry.symbol, category: entry.category,
                          spotAssets: entry.assets, liabilities: entry.borrows)
        }
        .sorted { $0.spotNet > $1.spotNet }
    }

    private var totalSpot: Decimal { byCategory.reduce(0) { $0 + $1.spotAssets } }
    private var totalLiabilities: Decimal { byCategory.reduce(0) { $0 + $1.liabilities } }
    private var netExposure: Decimal {
        byCategory.filter { $0.id != "stablecoin" }.reduce(0) { $0 + $1.spotNet }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary cards
                HStack(spacing: 12) {
                    summaryCard("Spot Total", value: totalSpot)
                    summaryCard("Derivatives", value: 0, subtitle: "Coming soon")
                    summaryCard("Net Exposure", value: netExposure, subtitle: "Excl. stablecoins")
                }

                // Toggle
                Picker("View", selection: $showByAsset) {
                    Text("By Category").tag(false)
                    Text("By Asset").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                if showByAsset {
                    assetTable
                } else {
                    categoryTable
                }
            }
            .padding()
        }
        .navigationTitle("Exposure")
    }

    // MARK: - Tables

    private var categoryTable: some View {
        Table(byCategory) {
            TableColumn("Category") { row in Text(row.name).fontWeight(.medium) }
                .width(min: 100, ideal: 140)
            TableColumn("Spot Assets") { row in
                Text(row.spotAssets, format: .currency(code: "USD"))
            }
            .width(min: 80, ideal: 120)
            TableColumn("Liabilities") { row in
                Text(row.liabilities, format: .currency(code: "USD"))
                    .foregroundStyle(row.liabilities > 0 ? .red : .secondary)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Spot Net") { row in
                Text(row.spotNet, format: .currency(code: "USD"))
                    .foregroundStyle(row.spotNet < 0 ? .red : .primary)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Derivatives") { _ in Text("—").foregroundStyle(.tertiary) }
                .width(min: 60, ideal: 80)
            TableColumn("Net Exposure") { row in
                Text(row.netExposure, format: .currency(code: "USD"))
                    .fontWeight(.medium)
            }
            .width(min: 80, ideal: 120)
        }
    }

    private var assetTable: some View {
        Table(byAsset) {
            TableColumn("Asset") { row in Text(row.symbol).fontWeight(.medium) }
                .width(min: 60, ideal: 80)
            TableColumn("Category") { row in
                Text(row.category.rawValue.capitalized)
                    .font(.caption)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Spot Assets") { row in
                Text(row.spotAssets, format: .currency(code: "USD"))
            }
            TableColumn("Liabilities") { row in
                Text(row.liabilities, format: .currency(code: "USD"))
                    .foregroundStyle(row.liabilities > 0 ? .red : .secondary)
            }
            TableColumn("Spot Net") { row in
                Text(row.spotNet, format: .currency(code: "USD"))
                    .foregroundStyle(row.spotNet < 0 ? .red : .primary)
            }
            TableColumn("Net Exposure") { row in
                Text(row.netExposure, format: .currency(code: "USD"))
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Helpers

    private func summaryCard(_ title: String, value: Decimal, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD"))
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tokenUSDValue(_ token: PositionToken) -> Decimal {
        token.asset?.coinGeckoId.flatMap { appState.prices[$0] }.map { token.amount * $0 }
            ?? token.usdValue
    }
}
```

- [ ] **Step 3: Wire into ContentView**

```swift
case .exposure:
    ExposureView()
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Portu/Features/Exposure/ Sources/Portu/App/ContentView.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add ExposureView with category and asset exposure tables

Pure computed view from live PositionTokens. Spot Assets, Liabilities,
Spot Net, Net Exposure (excl. stablecoins). Category/Asset toggle.
EOF
)"
```

---

### Task 2: Build and verify

- [ ] **Step 1: Build**

Run: `just build 2>&1 | tail -10`

- [ ] **Step 2: Commit any fixes**
