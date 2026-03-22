# Portu Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the scaffolding schema and service stubs with the DTO-driven data foundation, provider layer, snapshot persistence, and sync orchestration required by the full app.

**Architecture:** Keep `PortuNetwork` persistence-free and actor-isolated, move all SwiftData writes into an app-target `SyncEngine`, and split `PortuCore` between `@Model` classes and plain `Sendable` transport/value types. Use destructive migration to replace the old `Portfolio` / `Holding` schema cleanly before building higher-level features on top.

**Tech Stack:** Swift 6.2, SwiftData, Swift Testing, URLSession, Keychain Services, XcodeGen, actors

**Spec:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

**Skills to use:** @swift-architecture-skill, @swift-api-design-guidelines-skill, @swiftdata-pro, @swift-concurrency-pro, @swift-testing-pro, @swift-security-expert

**Dependencies:** Execute this plan before every other plan in this set.

---

## File Map

```
Portu/
├── Packages/
│   ├── PortuCore/
│   │   ├── Package.swift
│   │   ├── Sources/PortuCore/
│   │   │   ├── Keychain/
│   │   │   │   ├── KeychainError.swift
│   │   │   │   ├── KeychainKey.swift                    # new
│   │   │   │   └── KeychainService.swift
│   │   │   ├── Models/
│   │   │   │   ├── Account.swift
│   │   │   │   ├── AccountKind.swift
│   │   │   │   ├── Asset.swift
│   │   │   │   ├── AssetCategory.swift                 # new
│   │   │   │   ├── AccountSnapshot.swift               # new
│   │   │   │   ├── AssetSnapshot.swift                 # new
│   │   │   │   ├── Chain.swift
│   │   │   │   ├── DataSource.swift                    # new
│   │   │   │   ├── ExchangeType.swift
│   │   │   │   ├── PortfolioSnapshot.swift             # new
│   │   │   │   ├── Position.swift                      # new
│   │   │   │   ├── PositionToken.swift                 # new
│   │   │   │   ├── PositionType.swift                  # new
│   │   │   │   ├── TokenRole.swift                     # new
│   │   │   │   ├── WalletAddress.swift                 # new
│   │   │   │   └── Portfolio.swift                     # delete
│   │   │   ├── Protocols/SecretStore.swift
│   │   │   └── Sync/
│   │   │       ├── PositionDTO.swift                   # new
│   │   │       ├── ProviderCapabilities.swift          # new
│   │   │       ├── SnapshotStore.swift                 # new
│   │   │       ├── SyncContext.swift                   # new
│   │   │       └── TokenDTO.swift                      # new
│   │   └── Tests/PortuCoreTests/
│   │       ├── KeychainServiceTests.swift
│   │       ├── ModelTests.swift
│   │       ├── SnapshotStoreTests.swift                # new
│   │       └── TransportTypeTests.swift                # new
│   ├── PortuNetwork/
│   │   ├── Package.swift
│   │   ├── Sources/PortuNetwork/
│   │   │   ├── PortfolioDataProvider.swift            # new
│   │   │   ├── PriceService/
│   │   │   │   ├── CoinGeckoDTO.swift
│   │   │   │   ├── HistoricalPricePoint.swift        # new
│   │   │   │   ├── PriceService.swift
│   │   │   │   └── PriceServiceError.swift
│   │   │   └── Providers/
│   │   │       ├── Exchange/
│   │   │       │   ├── ExchangeProvider.swift         # new
│   │   │       │   ├── ExchangeProviderError.swift    # new
│   │   │       │   └── ExchangeResponseDTO.swift      # new
│   │   │       └── Zapper/
│   │   │           ├── ZapperProvider.swift           # new
│   │   │           ├── ZapperProviderError.swift      # new
│   │   │           └── ZapperResponseDTO.swift        # new
│   │   └── Tests/PortuNetworkTests/
│   │       ├── ExchangeProviderTests.swift            # new
│   │       ├── PriceServiceTests.swift
│   │       └── ZapperProviderTests.swift              # new
├── Sources/Portu/
│   ├── App/
│   │   ├── AppState.swift
│   │   ├── ModelContainerFactory.swift                # new
│   │   └── PortuApp.swift
│   └── Sync/
│       ├── ProviderFactory.swift                      # new
│       └── SyncEngine.swift                           # new
├── Tests/PortuTests/
│   ├── PortuAppTests.swift
│   └── SyncEngineTests.swift                          # new
└── project.yml
```

---

### Task 1: Replace the scaffolding schema with the full PortuCore model set

**Files:**
- Modify: `Packages/PortuCore/Package.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/Account.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/Asset.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/AccountKind.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/ExchangeType.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/Models/Chain.swift`
- Delete: `Packages/PortuCore/Sources/PortuCore/Models/Portfolio.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/DataSource.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/WalletAddress.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/Position.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PositionToken.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PositionType.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/TokenRole.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/AssetCategory.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PortfolioSnapshot.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/AccountSnapshot.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/AssetSnapshot.swift`
- Test: `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`

- [ ] **Step 1: Write failing model tests for the new schema**

```swift
@Test func accountStoresAddressesAndSyncMetadata() throws {
    let account = Account(
        name: "Main wallet",
        kind: .wallet,
        dataSource: .zapper
    )
    account.addresses = [WalletAddress(address: "0xabc", chain: nil)]

    #expect(account.isActive)
    #expect(account.addresses.count == 1)
    #expect(account.lastSyncError == nil)
}

@Test func positionNetValueUsesSignedTokenRoles() throws {
    let asset = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum")
    let position = Position(positionType: .lending, netUSDValue: 1000)
    position.tokens = [
        PositionToken(role: .supply, amount: 2, usdValue: 4000, asset: asset),
        PositionToken(role: .borrow, amount: 1, usdValue: 3000, asset: asset),
    ]

    #expect(position.netUSDValue == 1000)
    #expect(position.tokens.count == 2)
}
```

- [ ] **Step 2: Run the model tests to verify the current schema fails**

Run: `swift test --package-path Packages/PortuCore --filter ModelTests`

Expected: FAIL with missing `Account` initializer parameters, missing `WalletAddress` / `Position` / snapshot model types, and stale `Portfolio` / `Holding` assumptions.

- [ ] **Step 3: Implement the new model graph and remove the old `Portfolio` / `Holding` schema**

```swift
@Model
public final class Account {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var exchangeType: ExchangeType?
    public var dataSource: DataSource
    public var group: String?
    public var notes: String?
    public var lastSyncedAt: Date?
    public var lastSyncError: String?
    public var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \WalletAddress.account)
    public var addresses: [WalletAddress]

    @Relationship(deleteRule: .cascade, inverse: \Position.account)
    public var positions: [Position]
}
```

- [ ] **Step 4: Re-run the PortuCore model tests**

Run: `swift test --package-path Packages/PortuCore --filter ModelTests`

Expected: PASS with coverage for relationships, delete rules, and snapshot persistence entities.

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuCore/Package.swift Packages/PortuCore/Sources/PortuCore/Models Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift
git commit -m "feat: replace scaffolding schema with portfolio position models"
```

---

### Task 2: Add transport types, snapshot retention, and Keychain naming conventions

**Files:**
- Modify: `Packages/PortuCore/Sources/PortuCore/Keychain/KeychainError.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/Keychain/KeychainService.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/Protocols/SecretStore.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Keychain/KeychainKey.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Sync/SyncContext.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Sync/TokenDTO.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Sync/PositionDTO.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Sync/ProviderCapabilities.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Sync/SnapshotStore.swift`
- Modify: `Packages/PortuCore/Tests/PortuCoreTests/KeychainServiceTests.swift`
- Create: `Packages/PortuCore/Tests/PortuCoreTests/TransportTypeTests.swift`
- Create: `Packages/PortuCore/Tests/PortuCoreTests/SnapshotStoreTests.swift`

- [ ] **Step 1: Write failing tests for DTOs, snapshot pruning, and secret key naming**

```swift
@Test func syncContextCapturesAccountScope() {
    let context = SyncContext(
        accountId: UUID(),
        kind: .exchange,
        addresses: [],
        exchangeType: .kraken
    )

    #expect(context.exchangeType == .kraken)
}

@Test func snapshotStorePrunesDailyAndWeeklyBuckets() throws {
    let store = SnapshotStore()
    let pruned = store.prune(snapshotDates: sampleDates)
    #expect(pruned.count < sampleDates.count)
}

@Test func keychainKeysUseStableServicePrefixes() {
    #expect(KeychainKey.providerAPIKey(.zapper).service == "portu.provider.zapper.apiKey")
}
```

- [ ] **Step 2: Run the focused PortuCore tests and confirm they fail**

Run: `swift test --package-path Packages/PortuCore --filter 'TransportTypeTests|SnapshotStoreTests|KeychainServiceTests'`

Expected: FAIL because the DTOs, `SnapshotStore`, and `KeychainKey` do not exist yet and Keychain naming is still ad hoc.

- [ ] **Step 3: Implement the plain `Sendable` transport layer and a background-safe Keychain API**

```swift
public struct TokenDTO: Sendable {
    public let role: TokenRole
    public let symbol: String
    public let name: String
    public let amount: Decimal
    public let usdValue: Decimal
    public let chain: Chain?
    public let contractAddress: String?
    public let debankId: String?
    public let coinGeckoId: String?
    public let sourceKey: String?
    public let logoURL: String?
    public let category: AssetCategory
    public let isVerified: Bool
}
```

```swift
public enum KeychainKey: Sendable {
    case providerAPIKey(DataSource)
    case exchangeAPIKey(UUID)
    case exchangeAPISecret(UUID)
    case exchangePassphrase(UUID)
}
```

- [ ] **Step 4: Re-run the focused PortuCore tests**

Run: `swift test --package-path Packages/PortuCore --filter 'TransportTypeTests|SnapshotStoreTests|KeychainServiceTests'`

Expected: PASS with deterministic pruning behavior and stable key naming.

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuCore/Sources/PortuCore/Keychain Packages/PortuCore/Sources/PortuCore/Protocols/SecretStore.swift Packages/PortuCore/Sources/PortuCore/Sync Packages/PortuCore/Tests/PortuCoreTests
git commit -m "feat: add sync transport types and snapshot retention helpers"
```

---

### Task 3: Introduce the provider protocol and implement the first concrete providers

**Files:**
- Modify: `Packages/PortuNetwork/Package.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/PortfolioDataProvider.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Zapper/ZapperProvider.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Zapper/ZapperProviderError.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Zapper/ZapperResponseDTO.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/ExchangeProvider.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/ExchangeProviderError.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/Exchange/ExchangeResponseDTO.swift`
- Create: `Packages/PortuNetwork/Tests/PortuNetworkTests/ZapperProviderTests.swift`
- Create: `Packages/PortuNetwork/Tests/PortuNetworkTests/ExchangeProviderTests.swift`

- [ ] **Step 1: Write failing provider tests against `PortfolioDataProvider`**

```swift
@Test func zapperProviderMapsBalancesIntoPositionDTOs() async throws {
    let provider = ZapperProvider(session: mockedSession(json: zapperBalanceFixture))
    let context = SyncContext(
        accountId: UUID(),
        kind: .wallet,
        addresses: [(address: "0xabc", chain: nil)],
        exchangeType: nil
    )

    let balances = try await provider.fetchBalances(context: context)
    #expect(balances.count == 1)
    #expect(balances[0].tokens[0].coinGeckoId == "ethereum")
}
```

```swift
@Test func exchangeProviderRejectsMissingExchangeType() async {
    let provider = ExchangeProvider(secretStore: InMemorySecretStore())

    await #expect(throws: ExchangeProviderError.missingExchangeType) {
        _ = try await provider.fetchBalances(
            context: SyncContext(accountId: UUID(), kind: .exchange, addresses: [], exchangeType: nil)
        )
    }
}
```

- [ ] **Step 2: Run the PortuNetwork provider tests**

Run: `swift test --package-path Packages/PortuNetwork --filter 'ZapperProviderTests|ExchangeProviderTests'`

Expected: FAIL with missing provider types and missing DTO decoding/mapping code.

- [ ] **Step 3: Implement `PortfolioDataProvider`, Zapper, and exchange balance fetchers as isolated actors**

```swift
public protocol PortfolioDataProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func fetchBalances(context: SyncContext) async throws -> [PositionDTO]
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO]
}

public actor ZapperProvider: PortfolioDataProvider {
    public let capabilities = ProviderCapabilities(
        supportsTokenBalances: true,
        supportsDeFiPositions: true,
        supportsHealthFactors: true
    )
}
```

- [ ] **Step 4: Re-run the provider tests**

Run: `swift test --package-path Packages/PortuNetwork --filter 'ZapperProviderTests|ExchangeProviderTests'`

Expected: PASS with account-scoped mapping to `PositionDTO` / `TokenDTO` and provider capability coverage.

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuNetwork/Package.swift Packages/PortuNetwork/Sources/PortuNetwork/PortfolioDataProvider.swift Packages/PortuNetwork/Sources/PortuNetwork/Providers Packages/PortuNetwork/Tests/PortuNetworkTests/ZapperProviderTests.swift Packages/PortuNetwork/Tests/PortuNetworkTests/ExchangeProviderTests.swift
git commit -m "feat: add portfolio data providers for zapper and exchanges"
```

---

### Task 4: Upgrade `PriceService` for atomic live updates and historical data

**Files:**
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift`
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift`
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceServiceError.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/HistoricalPricePoint.swift`
- Modify: `Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift`

- [ ] **Step 1: Extend the price tests to cover atomic price + 24h change updates and history**

```swift
@Test func priceStreamYieldsPriceUpdatePayloads() async throws {
    let service = PriceService(session: session, cacheTTL: 0)
    let stream = await service.priceStream(for: ["bitcoin"], interval: 1)
    let update = try await #require(await stream.first { _ in true })

    #expect(update.prices["bitcoin"] == 62400)
    #expect(update.changes24h["bitcoin"] == 4.5)
}

@Test func historicalPricesDecodeChronologicalSeries() async throws {
    let series = try await service.fetchHistoricalPrices(for: "bitcoin", days: 30)
    #expect(series.count == 30)
}
```

- [ ] **Step 2: Run the `PriceService` tests**

Run: `swift test --package-path Packages/PortuNetwork --filter PriceServiceTests`

Expected: FAIL because `PriceUpdate`, history fetching, and 24h change decoding are not implemented.

- [ ] **Step 3: Refactor `PriceService` to publish a single `PriceUpdate` stream and historical series**

```swift
public struct PriceUpdate: Sendable {
    public let prices: [String: Decimal]
    public let changes24h: [String: Decimal]
}

public func priceStream(
    for coinIDs: [String],
    interval: TimeInterval = 30
) -> AsyncThrowingStream<PriceUpdate, any Error>
```

- [ ] **Step 4: Re-run the `PriceService` tests**

Run: `swift test --package-path Packages/PortuNetwork --filter PriceServiceTests`

Expected: PASS with live polling, rate limiting, cache invalidation, and historical-data decoding covered.

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuNetwork/Sources/PortuNetwork/PriceService Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift
git commit -m "feat: expand price service for market updates and history"
```

---

### Task 5: Build the app-target sync orchestration and destructive migration bootstrap

**Files:**
- Modify: `Sources/Portu/App/AppState.swift`
- Modify: `Sources/Portu/App/PortuApp.swift`
- Modify: `Tests/PortuTests/PortuAppTests.swift`
- Create: `Sources/Portu/App/ModelContainerFactory.swift`
- Create: `Sources/Portu/Sync/ProviderFactory.swift`
- Create: `Sources/Portu/Sync/SyncEngine.swift`
- Create: `Tests/PortuTests/SyncEngineTests.swift`
- Modify: `project.yml`

- [ ] **Step 1: Write failing app-target tests for sync and schema bootstrapping**

```swift
@Test func syncEngineMarksPartialFailuresButKeepsSnapshots() async throws {
    let harness = try SyncEngineHarness.make(oneSuccessOneFailure: true)
    try await harness.engine.syncAllAccounts()

    #expect(harness.appState.syncStatus == .completedWithErrors(failedAccounts: ["Cold Wallet"]))
    #expect(try harness.portfolioSnapshots().first?.isPartial == true)
}

@Test func modelContainerFactoryFallsBackToDestructiveReset() throws {
    let factory = ModelContainerFactory()
    let container = try factory.makeForProduction()
    #expect(container.mainContext != nil)
}
```

- [ ] **Step 2: Run the app tests to confirm the new sync path is missing**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/SyncEngineTests test`

Expected: FAIL with missing `SyncEngine`, `ProviderFactory`, `ModelContainerFactory`, and `SyncStatus`.

- [ ] **Step 3: Implement the app composition root**

```swift
@Observable
@MainActor
final class AppState {
    var selectedSection: SidebarSection = .overview
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]
    var priceChanges24h: [String: Decimal] = [:]
    var connectionStatus: ConnectionStatus = .idle
    var syncStatus: SyncStatus = .idle
}
```

```swift
@MainActor
final class SyncEngine {
    func syncAllAccounts() async throws {
        // fetch DTOs off-main, map into SwiftData on this actor, then append snapshots
    }
}
```

- [ ] **Step 4: Re-run the app tests and a full package smoke test**

Run: `xcodebuild -scheme Portu -destination 'platform=macOS' -only-testing:PortuTests/SyncEngineTests test`

Expected: PASS for app-target sync orchestration.

Run: `swift test --package-path Packages/PortuCore && swift test --package-path Packages/PortuNetwork`

Expected: PASS for the foundational package suite before UI plans begin.

- [ ] **Step 5: Commit**

```bash
git add Sources/Portu/App Sources/Portu/Sync Tests/PortuTests project.yml
git commit -m "feat: add sync engine and app bootstrap for full portfolio data flow"
```

