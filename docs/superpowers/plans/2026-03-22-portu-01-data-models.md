# Phase 1a: Data Models & DTOs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing scaffold data model with the production-ready schema from the Portu Full App Design Spec — SwiftData models, enums, and transport DTOs.

**Architecture:** PortuCore provides SwiftData `@Model` types (MainActor-isolated via the macro), plain `Sendable` enums, and transport DTOs. Default MainActor isolation is removed from the package — only `@Model` classes carry `@MainActor`, while enums and DTOs remain freely `Sendable` across isolation domains.

**IMPORTANT — Access Modifiers:** All types in PortuCore (enums, models, DTOs) **must be `public`** since they are used across module boundaries by PortuNetwork and the app target. Every `enum`, `struct`, `final class`, and their `init` methods need `public` access. The code samples below include `public` access modifiers.

**Tech Stack:** Swift 6.2, SwiftData, Swift Testing

**Spec Reference:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

---

## File Structure

### Delete
- `Packages/PortuCore/Sources/PortuCore/Models/Portfolio.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/Holding.swift`

### Create
- `Packages/PortuCore/Sources/PortuCore/Models/DataSource.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/PositionType.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/TokenRole.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/AssetCategory.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/WalletAddress.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/Position.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/PositionToken.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/PortfolioSnapshot.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/AccountSnapshot.swift`
- `Packages/PortuCore/Sources/PortuCore/Models/AssetSnapshot.swift`
- `Packages/PortuCore/Sources/PortuCore/DTOs/SyncContext.swift`
- `Packages/PortuCore/Sources/PortuCore/DTOs/PositionDTO.swift`
- `Packages/PortuCore/Sources/PortuCore/DTOs/TokenDTO.swift`
- `Packages/PortuCore/Sources/PortuCore/DTOs/PriceUpdate.swift`
- `Packages/PortuCore/Tests/PortuCoreTests/EnumTests.swift`
- `Packages/PortuCore/Tests/PortuCoreTests/DTOTests.swift`

### Modify
- `Packages/PortuCore/Package.swift` — remove `defaultIsolation(MainActor.self)`
- `Packages/PortuCore/Sources/PortuCore/Models/Chain.swift` — add missing chains
- `Packages/PortuCore/Sources/PortuCore/Models/Account.swift` — major rework
- `Packages/PortuCore/Sources/PortuCore/Models/Asset.swift` — major rework
- `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift` — rewrite for new schema
- `Sources/Portu/App/PortuApp.swift` — update ModelContainer schema

---

### Task 1: Remove default MainActor isolation from PortuCore

**Files:**
- Modify: `Packages/PortuCore/Package.swift`

Per spec: PortuCore has **no default isolation**. `@Model` types get `@MainActor` from the macro. Enums and DTOs must be freely `Sendable`.

- [ ] **Step 1: Update Package.swift**

```swift
// Packages/PortuCore/Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortuCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortuCore", targets: ["PortuCore"]),
    ],
    targets: [
        .target(
            name: "PortuCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "PortuCoreTests",
            dependencies: ["PortuCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path Packages/PortuCore 2>&1 | head -20`
Expected: Build errors from existing models referencing `Portfolio`/`Holding` (expected — we'll fix in next tasks)

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuCore/Package.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: remove default MainActor isolation from PortuCore

PortuCore enums and DTOs must be freely Sendable across isolation
domains. @Model types get @MainActor from the macro itself.
EOF
)"
```

---

### Task 2: Delete obsolete models

**Files:**
- Delete: `Packages/PortuCore/Sources/PortuCore/Models/Portfolio.swift`
- Delete: `Packages/PortuCore/Sources/PortuCore/Models/Holding.swift`
- Modify: `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`

The single-portfolio MVP eliminates the Portfolio model. Holding is replaced by PositionToken.

- [ ] **Step 1: Delete obsolete files**

```bash
rm Packages/PortuCore/Sources/PortuCore/Models/Portfolio.swift
rm Packages/PortuCore/Sources/PortuCore/Models/Holding.swift
```

- [ ] **Step 2: Gut the old ModelTests.swift** (will be rewritten in Task 12)

```swift
// Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift
import Testing
@testable import PortuCore

@Suite("Model Tests")
struct ModelTests {
    // Placeholder — rewritten after all models are defined
    @Test func placeholder() {
        #expect(true)
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build --package-path Packages/PortuCore 2>&1 | tail -5`
Expected: Build errors from Account.swift referencing deleted types (expected — Account rework is Task 9)

- [ ] **Step 4: Commit**

```bash
git add -A Packages/PortuCore/Sources/PortuCore/Models/Portfolio.swift \
          Packages/PortuCore/Sources/PortuCore/Models/Holding.swift \
          Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: delete Portfolio and Holding models

Single-portfolio MVP eliminates Portfolio. Holding is replaced by
PositionToken in the new data model.
EOF
)"
```

---

### Task 3: New foundation enums

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/DataSource.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PositionType.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/TokenRole.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/AssetCategory.swift`
- Create: `Packages/PortuCore/Tests/PortuCoreTests/EnumTests.swift`

- [ ] **Step 1: Write enum tests**

```swift
// Packages/PortuCore/Tests/PortuCoreTests/EnumTests.swift
import Testing
import Foundation
@testable import PortuCore

@Suite("Enum Tests")
struct EnumTests {

    // MARK: - DataSource

    @Test func dataSourceCases() {
        #expect(DataSource.allCases.count == 3)
        #expect(DataSource.allCases.contains(.zapper))
        #expect(DataSource.allCases.contains(.exchange))
        #expect(DataSource.allCases.contains(.manual))
    }

    @Test func dataSourceCodable() throws {
        let encoded = try JSONEncoder().encode(DataSource.zapper)
        let decoded = try JSONDecoder().decode(DataSource.self, from: encoded)
        #expect(decoded == .zapper)
    }

    // MARK: - PositionType

    @Test func positionTypeCases() {
        #expect(PositionType.allCases.count == 7)
    }

    @Test func positionTypeCodable() throws {
        let encoded = try JSONEncoder().encode(PositionType.liquidityPool)
        let decoded = try JSONDecoder().decode(PositionType.self, from: encoded)
        #expect(decoded == .liquidityPool)
    }

    // MARK: - TokenRole

    @Test func tokenRoleCases() {
        #expect(TokenRole.allCases.count == 6)
    }

    @Test func tokenRoleSignHelpers() {
        // Positive roles
        #expect(TokenRole.supply.isPositive)
        #expect(TokenRole.balance.isPositive)
        #expect(TokenRole.stake.isPositive)
        #expect(TokenRole.lpToken.isPositive)

        // Borrow
        #expect(TokenRole.borrow.isBorrow)
        #expect(!TokenRole.borrow.isPositive)
        #expect(!TokenRole.borrow.isReward)

        // Reward
        #expect(TokenRole.reward.isReward)
        #expect(!TokenRole.reward.isPositive)
        #expect(!TokenRole.reward.isBorrow)
    }

    @Test func tokenRoleCodable() throws {
        let encoded = try JSONEncoder().encode(TokenRole.lpToken)
        let decoded = try JSONDecoder().decode(TokenRole.self, from: encoded)
        #expect(decoded == .lpToken)
    }

    // MARK: - AssetCategory

    @Test func assetCategoryCases() {
        #expect(AssetCategory.allCases.count == 8)
    }

    @Test func assetCategoryCodable() throws {
        let encoded = try JSONEncoder().encode(AssetCategory.stablecoin)
        let decoded = try JSONDecoder().decode(AssetCategory.self, from: encoded)
        #expect(decoded == .stablecoin)
    }

    // MARK: - Chain

    @Test func chainCases() {
        #expect(Chain.allCases.count == 11)
        #expect(Chain.allCases.contains(.monad))
        #expect(Chain.allCases.contains(.katana))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path Packages/PortuCore 2>&1 | tail -10`
Expected: FAIL — `DataSource`, `PositionType`, `TokenRole`, `AssetCategory` not found

- [ ] **Step 3: Write DataSource enum**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/DataSource.swift
public enum DataSource: String, Codable, CaseIterable, Sendable {
    case zapper
    case exchange
    case manual
    // case debank  — deferred (paid API)
    // case rpc     — deferred
}
```

- [ ] **Step 4: Write PositionType enum**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/PositionType.swift
public enum PositionType: String, Codable, CaseIterable, Sendable {
    case idle
    case lending
    case liquidityPool
    case staking
    case farming
    case vesting
    case other
}
```

- [ ] **Step 5: Write TokenRole enum**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/TokenRole.swift
public enum TokenRole: String, Codable, CaseIterable, Sendable {
    case supply
    case borrow
    case reward
    case stake
    case lpToken
    case balance

    /// Whether this role contributes positively to aggregations
    public var isPositive: Bool {
        switch self {
        case .supply, .stake, .lpToken, .balance: true
        case .borrow, .reward: false
        }
    }

    /// Whether this role subtracts in aggregations
    public var isBorrow: Bool { self == .borrow }

    /// Whether this role is excluded from aggregations (unclaimed rewards)
    public var isReward: Bool { self == .reward }
}
```

- [ ] **Step 6: Write AssetCategory enum**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/AssetCategory.swift
public enum AssetCategory: String, Codable, CaseIterable, Sendable {
    case major
    case stablecoin
    case defi
    case meme
    case privacy
    case fiat
    case governance
    case other
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --package-path Packages/PortuCore 2>&1 | tail -10`
Expected: All enum tests pass (Chain test may fail — updated in Task 4)

- [ ] **Step 8: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/DataSource.swift \
        Packages/PortuCore/Sources/PortuCore/Models/PositionType.swift \
        Packages/PortuCore/Sources/PortuCore/Models/TokenRole.swift \
        Packages/PortuCore/Sources/PortuCore/Models/AssetCategory.swift \
        Packages/PortuCore/Tests/PortuCoreTests/EnumTests.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add DataSource, PositionType, TokenRole, AssetCategory enums

Foundation enums for the new data model. TokenRole includes sign
helper methods used by SyncEngine and aggregation formulas.
EOF
)"
```

---

### Task 4: Update Chain enum

**Files:**
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/Chain.swift`

Add missing chains: polygon, arbitrum, optimism, base, bsc, avalanche, monad, katana.

- [ ] **Step 1: Update Chain enum**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/Chain.swift
public enum Chain: String, Codable, CaseIterable, Sendable {
    case ethereum
    case polygon
    case arbitrum
    case optimism
    case base
    case bsc
    case solana
    case bitcoin
    case avalanche
    case monad
    case katana
}
```

- [ ] **Step 2: Run tests**

Run: `swift test --package-path Packages/PortuCore --filter EnumTests 2>&1 | tail -10`
Expected: `chainCases` passes (count == 11)

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/Chain.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: expand Chain enum with L2 and alt-chain support

Add polygon, arbitrum, optimism, base, bsc, avalanche, monad, katana
to support multi-chain position tracking.
EOF
)"
```

---

### Task 5: Asset model (rework)

**Files:**
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/Asset.swift`

Complete rework. Asset is shared reference data with 3-tier upsert key hierarchy (coinGeckoId → upsertChain+upsertContract → sourceKey). `logoURL` is `String?` (not `URL?`) because SwiftData doesn't support `URL` in predicates.

- [ ] **Step 1: Rewrite Asset.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/Asset.swift
import Foundation
import SwiftData

@Model
final class Asset {
    @Attribute(.unique) var id: UUID
    var symbol: String
    var name: String

    // Tier 1 upsert key — cross-chain canonical identity
    var coinGeckoId: String?

    // Tier 2 upsert key — single-chain token without coinGeckoId
    // Only set for tier 2 matches; nil for cross-chain assets (tier 1)
    var upsertChain: Chain?
    var upsertContract: String?

    // Tier 3 upsert key — provider-specific opaque ID
    var sourceKey: String?

    // Reserved for future DeBankProvider
    var debankId: String?

    // String, not URL — SwiftData predicate compatibility
    var logoURL: String?

    var category: AssetCategory
    var isVerified: Bool

    init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        coinGeckoId: String? = nil,
        upsertChain: Chain? = nil,
        upsertContract: String? = nil,
        sourceKey: String? = nil,
        debankId: String? = nil,
        logoURL: String? = nil,
        category: AssetCategory = .other,
        isVerified: Bool = false
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.coinGeckoId = coinGeckoId
        self.upsertChain = upsertChain
        self.upsertContract = upsertContract
        self.sourceKey = sourceKey
        self.debankId = debankId
        self.logoURL = logoURL
        self.category = category
        self.isVerified = isVerified
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path Packages/PortuCore 2>&1 | tail -5`
Expected: May still have errors from Account.swift (expected — fixed in Task 9)

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/Asset.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: rework Asset model with 3-tier upsert key hierarchy

coinGeckoId (cross-chain) → upsertChain+upsertContract (single-chain)
→ sourceKey (provider-specific). Supports deduplication across providers.
EOF
)"
```

---

### Task 6: WalletAddress model

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/WalletAddress.swift`

One WalletAddress per address string. `chain: nil` means EVM address — provider queries all EVM chains.

- [ ] **Step 1: Write WalletAddress.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/WalletAddress.swift
import Foundation
import SwiftData

@Model
final class WalletAddress {
    @Attribute(.unique) var id: UUID

    /// nil = EVM address (provider queries all EVM chains)
    /// Set (e.g., .solana) = restrict to that chain
    var chain: Chain?

    var address: String

    var account: Account?

    init(
        id: UUID = UUID(),
        chain: Chain? = nil,
        address: String,
        account: Account? = nil
    ) {
        self.id = id
        self.chain = chain
        self.address = address
        self.account = account
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/WalletAddress.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add WalletAddress model

Bridges Account to on-chain addresses. chain=nil means EVM address
queried across all supported EVM chains by the provider.
EOF
)"
```

---

### Task 7: PositionToken model

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PositionToken.swift`

Bridges Position ↔ Asset. `amount` and `usdValue` are ALWAYS POSITIVE — `TokenRole` provides the sign.

- [ ] **Step 1: Write PositionToken.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/PositionToken.swift
import Foundation
import SwiftData

@Model
final class PositionToken {
    @Attribute(.unique) var id: UUID

    var role: TokenRole

    /// ALWAYS POSITIVE — role provides the sign (see Sign Convention in spec)
    var amount: Decimal

    /// ALWAYS POSITIVE — role provides the sign (see Sign Convention in spec)
    var usdValue: Decimal

    /// N:1 — assets are shared reference data (nullify on delete)
    var asset: Asset?

    var position: Position?

    init(
        id: UUID = UUID(),
        role: TokenRole,
        amount: Decimal,
        usdValue: Decimal,
        asset: Asset? = nil,
        position: Position? = nil
    ) {
        self.id = id
        self.role = role
        self.amount = amount
        self.usdValue = usdValue
        self.asset = asset
        self.position = position
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/PositionToken.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add PositionToken model

Bridges Position and Asset. amount/usdValue always positive — TokenRole
provides sign semantics for aggregation formulas.
EOF
)"
```

---

### Task 8: Position model

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/Position.swift`

Core entity. `netUSDValue` is pre-computed by SyncEngine from token roles.

- [ ] **Step 1: Write Position.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/Position.swift
import Foundation
import SwiftData

@Model
final class Position {
    @Attribute(.unique) var id: UUID

    var positionType: PositionType

    /// nil = off-chain (exchange custody, manual entry)
    var chain: Chain?

    /// Zapper protocol identifier (future: DeBank)
    var protocolId: String?
    var protocolName: String?

    /// String, not URL — SwiftData predicate compatibility
    var protocolLogoURL: String?

    /// Lending positions only
    var healthFactor: Double?

    /// Pre-computed signed total by SyncEngine:
    /// sum(+role usdValues) − sum(borrow usdValues)
    var netUSDValue: Decimal

    @Relationship(deleteRule: .cascade, inverse: \PositionToken.position)
    var tokens: [PositionToken]

    var account: Account?

    var syncedAt: Date

    init(
        id: UUID = UUID(),
        positionType: PositionType,
        chain: Chain? = nil,
        protocolId: String? = nil,
        protocolName: String? = nil,
        protocolLogoURL: String? = nil,
        healthFactor: Double? = nil,
        netUSDValue: Decimal = 0,
        tokens: [PositionToken] = [],
        account: Account? = nil,
        syncedAt: Date = .now
    ) {
        self.id = id
        self.positionType = positionType
        self.chain = chain
        self.protocolId = protocolId
        self.protocolName = protocolName
        self.protocolLogoURL = protocolLogoURL
        self.healthFactor = healthFactor
        self.netUSDValue = netUSDValue
        self.tokens = tokens
        self.account = account
        self.syncedAt = syncedAt
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/Position.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add Position model

Core entity for DeFi positions, staking, LP, and idle balances.
netUSDValue pre-computed by SyncEngine from token role signs.
EOF
)"
```

---

### Task 9: Rework Account model

**Files:**
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/Account.swift`

Major rework: remove Portfolio relationship, add dataSource, addresses, positions, isActive, lastSyncError.

- [ ] **Step 1: Rewrite Account.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/Account.swift
import Foundation
import SwiftData

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var name: String
    var kind: AccountKind
    var exchangeType: ExchangeType?
    var dataSource: DataSource

    @Relationship(deleteRule: .cascade, inverse: \WalletAddress.account)
    var addresses: [WalletAddress]

    @Relationship(deleteRule: .cascade, inverse: \Position.account)
    var positions: [Position]

    var group: String?
    var notes: String?
    var lastSyncedAt: Date?

    /// nil = no error; set on failed sync, cleared on success
    var lastSyncError: String?

    /// Inactive accounts are soft-hidden: excluded from sync, snapshots, and all views
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind,
        exchangeType: ExchangeType? = nil,
        dataSource: DataSource,
        addresses: [WalletAddress] = [],
        positions: [Position] = [],
        group: String? = nil,
        notes: String? = nil,
        lastSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.exchangeType = exchangeType
        self.dataSource = dataSource
        self.addresses = addresses
        self.positions = positions
        self.group = group
        self.notes = notes
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncError = lastSyncError
        self.isActive = isActive
    }
}
```

- [ ] **Step 2: Verify PortuCore compiles**

Run: `swift build --package-path Packages/PortuCore 2>&1 | tail -10`
Expected: SUCCESS (all models now defined)

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/Account.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: rework Account model for new data schema

Remove Portfolio relationship (single-portfolio MVP). Add dataSource,
addresses, positions, isActive, lastSyncError. Cascade-deletes
WalletAddress and Position children.
EOF
)"
```

---

### Task 10: Snapshot models

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PortfolioSnapshot.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/AccountSnapshot.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/AssetSnapshot.swift`

Three tiers of append-only time series. All share `syncBatchId` per batch. Snapshot fields use UUID keys (not relationships) — historical data survives account/asset deletion.

- [ ] **Step 1: Write PortfolioSnapshot.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/PortfolioSnapshot.swift
import Foundation
import SwiftData

@Model
final class PortfolioSnapshot {
    @Attribute(.unique) var id: UUID
    var syncBatchId: UUID
    var timestamp: Date
    var totalValue: Decimal
    var idleValue: Decimal
    var deployedValue: Decimal
    var debtValue: Decimal

    /// true if any account failed during this sync batch
    var isPartial: Bool

    init(
        id: UUID = UUID(),
        syncBatchId: UUID,
        timestamp: Date,
        totalValue: Decimal,
        idleValue: Decimal,
        deployedValue: Decimal,
        debtValue: Decimal,
        isPartial: Bool
    ) {
        self.id = id
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.totalValue = totalValue
        self.idleValue = idleValue
        self.deployedValue = deployedValue
        self.debtValue = debtValue
        self.isPartial = isPartial
    }
}
```

- [ ] **Step 2: Write AccountSnapshot.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/AccountSnapshot.swift
import Foundation
import SwiftData

@Model
final class AccountSnapshot {
    @Attribute(.unique) var id: UUID
    var syncBatchId: UUID
    var timestamp: Date

    /// Not a relationship — survives account deletion for historical data
    var accountId: UUID

    var totalValue: Decimal

    /// true = synced successfully or manual account; false = remote sync failed
    var isFresh: Bool

    init(
        id: UUID = UUID(),
        syncBatchId: UUID,
        timestamp: Date,
        accountId: UUID,
        totalValue: Decimal,
        isFresh: Bool
    ) {
        self.id = id
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.accountId = accountId
        self.totalValue = totalValue
        self.isFresh = isFresh
    }
}
```

- [ ] **Step 3: Write AssetSnapshot.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/Models/AssetSnapshot.swift
import Foundation
import SwiftData

@Model
final class AssetSnapshot {
    @Attribute(.unique) var id: UUID
    var syncBatchId: UUID
    var timestamp: Date

    /// Not a relationship — survives deletion
    var accountId: UUID
    var assetId: UUID

    /// Denormalized for display — survives Asset changes
    var symbol: String
    var category: AssetCategory

    /// GROSS POSITIVE: sum of supply + balance + stake + lpToken roles
    var amount: Decimal
    var usdValue: Decimal

    /// ABSOLUTE POSITIVE: borrow role tokens only, 0 if none
    var borrowAmount: Decimal
    var borrowUsdValue: Decimal

    init(
        id: UUID = UUID(),
        syncBatchId: UUID,
        timestamp: Date,
        accountId: UUID,
        assetId: UUID,
        symbol: String,
        category: AssetCategory,
        amount: Decimal,
        usdValue: Decimal,
        borrowAmount: Decimal = 0,
        borrowUsdValue: Decimal = 0
    ) {
        self.id = id
        self.syncBatchId = syncBatchId
        self.timestamp = timestamp
        self.accountId = accountId
        self.assetId = assetId
        self.symbol = symbol
        self.category = category
        self.amount = amount
        self.usdValue = usdValue
        self.borrowAmount = borrowAmount
        self.borrowUsdValue = borrowUsdValue
    }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build --package-path Packages/PortuCore 2>&1 | tail -5`
Expected: SUCCESS

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Models/PortfolioSnapshot.swift \
        Packages/PortuCore/Sources/PortuCore/Models/AccountSnapshot.swift \
        Packages/PortuCore/Sources/PortuCore/Models/AssetSnapshot.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add three-tier snapshot models

PortfolioSnapshot (totals), AccountSnapshot (per-account), AssetSnapshot
(per-asset per-account). All share syncBatchId per batch. UUID keys
instead of relationships for historical data durability.
EOF
)"
```

---

### Task 11: Transport DTOs

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/DTOs/SyncContext.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/DTOs/PositionDTO.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/DTOs/TokenDTO.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/DTOs/PriceUpdate.swift`
- Create: `Packages/PortuCore/Tests/PortuCoreTests/DTOTests.swift`

Plain `Sendable` structs — the transport format between PortuNetwork and the persistence layer. No SwiftData dependency.

- [ ] **Step 1: Create DTOs directory**

```bash
mkdir -p Packages/PortuCore/Sources/PortuCore/DTOs
```

- [ ] **Step 2: Write DTO tests**

```swift
// Packages/PortuCore/Tests/PortuCoreTests/DTOTests.swift
import Testing
import Foundation
@testable import PortuCore

@Suite("DTO Tests")
struct DTOTests {

    @Test func syncContextCreation() {
        let ctx = SyncContext(
            accountId: UUID(),
            kind: .wallet,
            addresses: [("0xabc", nil), ("SoL123", .solana)],
            exchangeType: nil
        )
        #expect(ctx.kind == .wallet)
        #expect(ctx.addresses.count == 2)
        #expect(ctx.addresses[0].chain == nil) // EVM — all chains
        #expect(ctx.addresses[1].chain == .solana)
    }

    @Test func positionDTOCreation() {
        let token = TokenDTO(
            role: .balance,
            symbol: "ETH",
            name: "Ethereum",
            amount: 10,
            usdValue: 21880,
            chain: .ethereum,
            contractAddress: nil,
            debankId: nil,
            coinGeckoId: "ethereum",
            sourceKey: nil,
            logoURL: nil,
            category: .major,
            isVerified: true
        )
        let pos = PositionDTO(
            positionType: .idle,
            chain: .ethereum,
            protocolId: nil,
            protocolName: nil,
            protocolLogoURL: nil,
            healthFactor: nil,
            tokens: [token]
        )
        #expect(pos.tokens.count == 1)
        #expect(pos.tokens[0].symbol == "ETH")
        #expect(pos.positionType == .idle)
    }

    @Test func tokenDTOAmountsArePositive() {
        // Borrow tokens still carry positive values — role provides sign
        let borrow = TokenDTO(
            role: .borrow,
            symbol: "USDC",
            name: "USD Coin",
            amount: 5000,
            usdValue: 5000,
            chain: .ethereum,
            contractAddress: "0xa0b8...",
            debankId: nil,
            coinGeckoId: "usd-coin",
            sourceKey: nil,
            logoURL: nil,
            category: .stablecoin,
            isVerified: true
        )
        #expect(borrow.amount > 0)
        #expect(borrow.usdValue > 0)
        #expect(borrow.role == .borrow)
    }

    @Test func priceUpdateCreation() {
        let update = PriceUpdate(
            prices: ["ethereum": 2188, "bitcoin": 67500],
            changes24h: ["ethereum": Decimal(string: "0.032")!, "bitcoin": Decimal(string: "-0.015")!]
        )
        #expect(update.prices.count == 2)
        #expect(update.changes24h["ethereum"]! > 0)
        #expect(update.changes24h["bitcoin"]! < 0)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --package-path Packages/PortuCore --filter DTOTests 2>&1 | tail -10`
Expected: FAIL — `SyncContext`, `PositionDTO`, etc. not found

- [ ] **Step 4: Write SyncContext.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/DTOs/SyncContext.swift
import Foundation

/// Lightweight DTO constructed by SyncEngine from an Account @Model.
/// Carries only the data a provider needs — no SwiftData types.
public struct SyncContext: Sendable {
    public let accountId: UUID
    public let kind: AccountKind
    public let addresses: [(address: String, chain: Chain?)]
    public let exchangeType: ExchangeType?

    public init(accountId: UUID, kind: AccountKind, addresses: [(address: String, chain: Chain?)], exchangeType: ExchangeType?) {
        self.accountId = accountId
        self.kind = kind
        self.addresses = addresses
        self.exchangeType = exchangeType
    }
}
```

- [ ] **Step 5: Write PositionDTO.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/DTOs/PositionDTO.swift
import Foundation

/// Returned by PortfolioDataProvider. SyncEngine maps these to @Model objects.
/// netUSDValue is NOT here — SyncEngine computes it from token roles.
public struct PositionDTO: Sendable {
    let positionType: PositionType
    let chain: Chain?
    let protocolId: String?
    let protocolName: String?
    let protocolLogoURL: String?
    let healthFactor: Double?
    let tokens: [TokenDTO]
}
```

- [ ] **Step 6: Write TokenDTO.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/DTOs/TokenDTO.swift
import Foundation

/// Carries inline asset metadata — there is no separate AssetDTO.
/// amount and usdValue are ALWAYS POSITIVE (role provides sign).
public struct TokenDTO: Sendable {
    let role: TokenRole
    let symbol: String
    let name: String
    let amount: Decimal
    let usdValue: Decimal
    let chain: Chain?
    let contractAddress: String?
    let debankId: String?
    let coinGeckoId: String?
    let sourceKey: String?
    let logoURL: String?
    let category: AssetCategory
    let isVerified: Bool
}
```

- [ ] **Step 7: Write PriceUpdate.swift**

```swift
// Packages/PortuCore/Sources/PortuCore/DTOs/PriceUpdate.swift
import Foundation

/// Published by PriceService. AppState subscribes and updates both maps atomically.
public struct PriceUpdate: Sendable {
    /// coinGeckoId → USD price
    let prices: [String: Decimal]
    /// coinGeckoId → 24h percentage change
    let changes24h: [String: Decimal]
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --package-path Packages/PortuCore --filter DTOTests 2>&1 | tail -10`
Expected: All DTO tests PASS

- [ ] **Step 9: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/DTOs/ \
        Packages/PortuCore/Tests/PortuCoreTests/DTOTests.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
feat: add transport DTOs (SyncContext, PositionDTO, TokenDTO, PriceUpdate)

Plain Sendable structs for the provider → SyncEngine boundary.
No SwiftData dependency. Asset metadata carried inline on TokenDTO.
EOF
)"
```

---

### Task 12: Model relationship and integration tests

**Files:**
- Modify: `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`

Test all model creation, relationships, and cascade delete behavior using in-memory SwiftData container.

- [ ] **Step 1: Rewrite ModelTests.swift**

```swift
// Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift
import Testing
import Foundation
import SwiftData
@testable import PortuCore

/// Helper to create an in-memory ModelContainer with all model types
@MainActor
func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Account.self,
        WalletAddress.self,
        Position.self,
        PositionToken.self,
        Asset.self,
        PortfolioSnapshot.self,
        AccountSnapshot.self,
        AssetSnapshot.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

@Suite("Model Tests")
@MainActor
struct ModelTests {

    // MARK: - Account creation

    @Test func createAccount() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let account = Account(
            name: "My Wallet",
            kind: .wallet,
            dataSource: .zapper
        )
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Account>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "My Wallet")
        #expect(fetched[0].kind == .wallet)
        #expect(fetched[0].dataSource == .zapper)
        #expect(fetched[0].isActive == true)
        #expect(fetched[0].lastSyncError == nil)
    }

    // MARK: - Account → WalletAddress cascade

    @Test func accountCascadeDeletesAddresses() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", kind: .wallet, dataSource: .zapper)
        let addr = WalletAddress(address: "0xabc123")
        account.addresses.append(addr)
        context.insert(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<WalletAddress>()).count == 1)

        context.delete(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<WalletAddress>()).count == 0)
    }

    // MARK: - Account → Position cascade

    @Test func accountCascadeDeletesPositions() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let account = Account(name: "Test", kind: .wallet, dataSource: .zapper)
        let position = Position(positionType: .idle, chain: .ethereum, netUSDValue: 1000)
        account.positions.append(position)
        context.insert(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Position>()).count == 1)

        context.delete(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Position>()).count == 0)
    }

    // MARK: - Position → PositionToken cascade

    @Test func positionCascadeDeletesTokens() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let asset = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        context.insert(asset)

        let token = PositionToken(role: .balance, amount: 10, usdValue: 21880, asset: asset)
        let position = Position(positionType: .idle, chain: .ethereum, netUSDValue: 21880, tokens: [token])
        context.insert(position)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PositionToken>()).count == 1)

        context.delete(position)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PositionToken>()).count == 0)
        // Asset survives — shared reference data, not cascade-deleted
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    // MARK: - PositionToken → Asset nullify

    @Test func deletingAssetNullifiesTokenReference() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let asset = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        let token = PositionToken(role: .balance, amount: 10, usdValue: 21880, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 21880, tokens: [token])
        context.insert(position)
        context.insert(asset)
        try context.save()

        context.delete(asset)
        try context.save()

        let tokens = try context.fetch(FetchDescriptor<PositionToken>())
        #expect(tokens.count == 1)
        #expect(tokens[0].asset == nil)
    }

    // MARK: - Full cascade: Account → Position → PositionToken

    @Test func fullCascadeDeleteChain() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let asset = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin", category: .major)
        let token = PositionToken(role: .balance, amount: 1, usdValue: 67500, asset: asset)
        let position = Position(positionType: .idle, netUSDValue: 67500, tokens: [token])
        let account = Account(name: "Hardware", kind: .wallet, dataSource: .zapper, positions: [position])
        context.insert(account)
        context.insert(asset)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Position>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PositionToken>()).count == 1)

        context.delete(account)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Account>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<Position>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<PositionToken>()).count == 0)
        // Asset survives
        #expect(try context.fetch(FetchDescriptor<Asset>()).count == 1)
    }

    // MARK: - Snapshot independence from models

    @Test func snapshotsUseUUIDKeysNotRelationships() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let accountId = UUID()
        let assetId = UUID()
        let batchId = UUID()
        let now = Date.now

        let portfolioSnap = PortfolioSnapshot(
            syncBatchId: batchId, timestamp: now,
            totalValue: 100000, idleValue: 50000,
            deployedValue: 45000, debtValue: 5000, isPartial: false
        )
        let accountSnap = AccountSnapshot(
            syncBatchId: batchId, timestamp: now,
            accountId: accountId, totalValue: 50000, isFresh: true
        )
        let assetSnap = AssetSnapshot(
            syncBatchId: batchId, timestamp: now,
            accountId: accountId, assetId: assetId,
            symbol: "ETH", category: .major,
            amount: 10, usdValue: 21880
        )

        context.insert(portfolioSnap)
        context.insert(accountSnap)
        context.insert(assetSnap)
        try context.save()

        // Snapshots exist independently — no Account or Asset record needed
        #expect(try context.fetch(FetchDescriptor<PortfolioSnapshot>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AccountSnapshot>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetSnapshot>()).count == 1)

        // syncBatchId links them
        let fetched = try context.fetch(FetchDescriptor<AssetSnapshot>())
        #expect(fetched[0].syncBatchId == batchId)
        #expect(fetched[0].borrowAmount == 0)
    }

    // MARK: - isActive default

    @Test func accountIsActiveByDefault() throws {
        let account = Account(name: "Test", kind: .wallet, dataSource: .zapper)
        #expect(account.isActive == true)
    }

    // MARK: - WalletAddress chain semantics

    @Test func evmAddressHasNilChain() throws {
        let addr = WalletAddress(address: "0xabc")
        #expect(addr.chain == nil) // EVM — provider queries all chains
    }

    @Test func solanaAddressHasExplicitChain() throws {
        let addr = WalletAddress(chain: .solana, address: "SoL123abc")
        #expect(addr.chain == .solana)
    }
}
```

- [ ] **Step 2: Run all PortuCore tests**

Run: `swift test --package-path Packages/PortuCore 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
test: rewrite model tests for new data schema

Tests cover Account/Position/PositionToken creation, cascade delete
chains, Asset nullify semantics, snapshot independence, WalletAddress
chain semantics, and isActive defaults.
EOF
)"
```

---

### Task 13: Update PortuApp ModelContainer

**Files:**
- Modify: `Sources/Portu/App/PortuApp.swift`

Register all new model types. Use destructive migration since only scaffold data exists.

- [ ] **Step 1: Update PortuApp.swift ModelContainer**

Update the `ModelContainer` initialization to include all new types:

```swift
// In PortuApp.swift, update the schema to include:
let schema = Schema([
    Account.self,
    WalletAddress.self,
    Position.self,
    PositionToken.self,
    Asset.self,
    PortfolioSnapshot.self,
    AccountSnapshot.self,
    AssetSnapshot.self,
])
```

Remove any references to the deleted `Portfolio` and `Holding` models. The container should use the new schema with `isStoredInMemoryOnly: false` for production and in-memory for the ephemeral fallback.

**Note:** Since the schema has changed completely, existing local data will be wiped. This is expected — the app has no real user data yet.

- [ ] **Step 2: Build the main app**

Run: `just build 2>&1 | tail -20`
Expected: SUCCESS — main app compiles with new models

- [ ] **Step 3: Commit**

```bash
git add Sources/Portu/App/PortuApp.swift
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor: update ModelContainer for new data schema

Register all new model types. Remove obsolete Portfolio/Holding.
Destructive migration — no real user data to preserve.
EOF
)"
```

---

### Task 14: Verify full test suite

- [ ] **Step 1: Run all package tests**

Run: `just test-packages 2>&1 | tail -30`
Expected: All PortuCore tests PASS (PortuNetwork and PortuUI may have unrelated issues from AppState changes — those are addressed in Plan 2)

- [ ] **Step 2: Fix any compilation errors**

If PortuNetwork or PortuUI tests fail to compile due to removed types, update imports. These packages should not directly reference `Portfolio` or `Holding`.

- [ ] **Step 3: Final commit if any fixes needed**

```bash
git add -A
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
fix: resolve compilation errors from schema migration
EOF
)"
```
