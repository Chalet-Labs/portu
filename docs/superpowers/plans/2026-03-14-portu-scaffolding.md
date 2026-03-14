# Portu SwiftUI App Scaffolding — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold a compilable, runnable SwiftUI macOS app with modular SPM packages, SwiftData models, Keychain integration, and a NavigationSplitView shell — producing the foundation for the Portu crypto portfolio dashboard.

**Architecture:** XcodeGen generates the .xcodeproj from `project.yml`. Three local SPM packages (PortuCore, PortuNetwork, PortuUI) provide domain models, networking stubs, and reusable UI components. The app target is the composition root that imports all packages and wires features together.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, macOS 15.0+, XcodeGen, Swift Testing, default MainActor isolation (SE-0466)

**Spec:** `docs/superpowers/specs/2026-03-14-portu-swiftui-app-design.md`

**Skills to use:** @swiftui-pro, @swiftdata-pro, @swift-testing-pro, @swift-concurrency-pro

---

## File Map

Every file the scaffolding creates. Files are grouped by task.

```
Portu/
├── .gitignore                                          # Task 1
├── justfile                                            # Task 1
├── scripts/
│   ├── generate.sh                                     # Task 1
│   └── build.sh                                        # Task 1
├── Packages/
│   ├── PortuCore/
│   │   ├── Package.swift                               # Task 2
│   │   ├── Sources/PortuCore/
│   │   │   ├── Models/
│   │   │   │   ├── Portfolio.swift                     # Task 3
│   │   │   │   ├── Account.swift                       # Task 3
│   │   │   │   ├── Holding.swift                       # Task 3
│   │   │   │   ├── Asset.swift                         # Task 3
│   │   │   │   ├── AccountKind.swift                   # Task 2
│   │   │   │   ├── ExchangeType.swift                  # Task 2
│   │   │   │   └── Chain.swift                         # Task 2
│   │   │   ├── Keychain/
│   │   │   │   ├── KeychainError.swift                 # Task 4
│   │   │   │   └── KeychainService.swift               # Task 4
│   │   │   └── Protocols/
│   │   │       └── SecretStore.swift                   # Task 4
│   │   └── Tests/PortuCoreTests/
│   │       ├── ModelTests.swift                        # Task 5
│   │       └── KeychainServiceTests.swift              # Task 5
│   ├── PortuNetwork/
│   │   ├── Package.swift                               # Task 6
│   │   ├── Sources/PortuNetwork/
│   │   │   └── PriceService/
│   │   │       ├── PriceServiceError.swift             # Task 6
│   │   │       ├── CoinGeckoDTO.swift                  # Task 7
│   │   │       └── PriceService.swift                  # Task 7
│   │   └── Tests/PortuNetworkTests/
│   │       └── PriceServiceTests.swift                 # Task 8
│   └── PortuUI/
│       ├── Package.swift                               # Task 9
│       ├── Sources/PortuUI/
│       │   ├── Components/
│       │   │   ├── StatCard.swift                      # Task 9
│       │   │   └── CurrencyText.swift                  # Task 9
│       │   └── Theme/
│       │       └── PortuTheme.swift                    # Task 9
│       └── Tests/PortuUITests/
│           └── PortuUITests.swift                      # Task 9
├── project.yml                                         # Task 10
├── Sources/Portu/
│   ├── App/
│   │   ├── PortuApp.swift                              # Task 11
│   │   └── AppState.swift                              # Task 11
│   ├── Features/
│   │   ├── Sidebar/
│   │   │   └── SidebarView.swift                       # Task 12
│   │   ├── Portfolio/
│   │   │   └── PortfolioView.swift                     # Task 13
│   │   ├── Accounts/
│   │   │   └── AccountDetailView.swift                 # Task 14
│   │   └── Settings/
│   │       └── SettingsView.swift                      # Task 14
│   └── Resources/
│       ├── Assets.xcassets/
│       │   ├── Contents.json                           # Task 10
│       │   ├── AccentColor.colorset/Contents.json      # Task 10
│       │   └── AppIcon.appiconset/Contents.json        # Task 10
│       ├── Portu.entitlements                          # Task 10
│       └── Info.plist                                  # Task 10
└── Tests/PortuTests/
    └── PortuAppTests.swift                             # Task 15
```

---

## Chunk 1: Infrastructure + PortuCore

### Task 1: Project infrastructure

**Files:**
- Create: `.gitignore`
- Create: `justfile`
- Create: `scripts/generate.sh`
- Create: `scripts/build.sh`

- [ ] **Step 1: Create .gitignore**

```gitignore
# Xcode
*.xcodeproj
*.xcworkspace
xcuserdata/
DerivedData/
*.xcuserstate

# Swift Package Manager
.build/
.swiftpm/
Package.resolved

# macOS
.DS_Store
*.swp
*~

# Build artifacts
build/
```

- [ ] **Step 2: Create justfile**

```just
# Portu — SwiftUI macOS Crypto Portfolio Dashboard

default:
    @just --list

# Generate Xcode project from project.yml
generate:
    xcodegen generate
    @echo "Project generated. Open Portu.xcodeproj"

# Build the app (Debug)
build:
    xcodebuild -scheme Portu -configuration Debug build

# Build the app (Release)
release:
    xcodebuild -scheme Portu -configuration Release build

# Run all tests (SPM packages)
test-packages:
    cd Packages/PortuCore && swift test
    cd Packages/PortuNetwork && swift test
    cd Packages/PortuUI && swift test

# Run all tests (Xcode scheme)
test:
    xcodebuild -scheme Portu -configuration Debug test

# Clean build artifacts
clean:
    xcodebuild -scheme Portu clean
    rm -rf DerivedData .build
```

- [ ] **Step 3: Create scripts/generate.sh**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
echo "✓ Portu.xcodeproj generated"
```

- [ ] **Step 4: Create scripts/build.sh**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
xcodebuild -scheme Portu -configuration "$CONFIG" build
echo "✓ Build complete ($CONFIG)"
```

- [ ] **Step 5: Make scripts executable**

Run: `chmod +x scripts/generate.sh scripts/build.sh`

- [ ] **Step 6: Commit**

```bash
git add .gitignore justfile scripts/
git commit -m "chore: add project infrastructure files"
```

---

### Task 2: PortuCore Package.swift + supporting enums

**Files:**
- Create: `Packages/PortuCore/Package.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/AccountKind.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/ExchangeType.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/Chain.swift`

- [ ] **Step 1: Create Package.swift**

```swift
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
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "PortuCoreTests",
            dependencies: ["PortuCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create AccountKind.swift**

```swift
import Foundation

/// Flat enum for account classification. No associated values — safe for SwiftData predicates.
/// Use `Account.exchangeType` and `Account.chain` for type-specific metadata.
public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case manual
    case exchange
    case wallet
}
```

- [ ] **Step 3: Create ExchangeType.swift**

```swift
import Foundation

public enum ExchangeType: String, Codable, CaseIterable, Sendable {
    case binance
    case coinbase
    case kraken
}
```

- [ ] **Step 4: Create Chain.swift**

```swift
import Foundation

public enum Chain: String, Codable, CaseIterable, Sendable {
    case ethereum
    case solana
    case bitcoin
}
```

- [ ] **Step 5: Verify package compiles**

Run: `cd Packages/PortuCore && swift build`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Packages/PortuCore/
git commit -m "feat: add PortuCore package with supporting enums"
```

---

### Task 3: SwiftData models

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/Portfolio.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/Account.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/Holding.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/Asset.swift`

**SwiftData rules (from @swiftdata-pro):**
- `@Relationship` on ONE side only per relationship, with explicit `inverse:`
- Properties with `.nullify` delete rule MUST be optional (non-optional + nullify = crash)
- No property named `description`
- No property observers on `@Model` classes
- Explicit `save()` for correctness (autosave timing is unpredictable)

- [ ] **Step 1: Create Portfolio.swift**

```swift
import Foundation
import SwiftData

@Model
public final class Portfolio {
    public var id: UUID
    public var name: String
    @Relationship(deleteRule: .cascade, inverse: \Account.portfolio)
    public var accounts: [Account]
    public var createdAt: Date

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.accounts = []
        self.createdAt = .now
    }
}
```

- [ ] **Step 2: Create Account.swift**

```swift
import Foundation
import SwiftData

@Model
public final class Account {
    public var id: UUID
    public var name: String
    public var kind: AccountKind
    public var exchangeType: ExchangeType?
    public var chain: Chain?
    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    public var holdings: [Holding]
    public var lastSyncedAt: Date?

    // Back-reference — nullify delete rule (set to nil when Portfolio is deleted).
    // @Relationship is on the Portfolio side; this is the inverse target.
    public var portfolio: Portfolio?

    public init(name: String, kind: AccountKind) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.holdings = []
    }
}
```

- [ ] **Step 3: Create Holding.swift**

```swift
import Foundation
import SwiftData

@Model
public final class Holding {
    public var id: UUID
    public var amount: Decimal
    public var costBasis: Decimal?

    // Back-reference — nullify (set to nil when Account is deleted via cascade).
    // @Relationship is on the Account side.
    public var account: Account?

    // Many-to-one with Asset. @Relationship on this side because Asset.holdings
    // is the inverse. nullify = optional.
    @Relationship(deleteRule: .nullify, inverse: \Asset.holdings)
    public var asset: Asset?

    public init(amount: Decimal, costBasis: Decimal? = nil) {
        self.id = UUID()
        self.amount = amount
        self.costBasis = costBasis
    }
}
```

- [ ] **Step 4: Create Asset.swift**

```swift
import Foundation
import SwiftData

@Model
public final class Asset {
    public var id: UUID
    public var symbol: String
    public var name: String
    public var coinGeckoId: String
    public var chain: Chain?
    public var contractAddress: String?

    // Back-reference from Holding.asset. No @Relationship here — it's on Holding side.
    // nullify = optional. Assets are shared reference data, never cascade-deleted.
    public var holdings: [Holding]

    public init(symbol: String, name: String, coinGeckoId: String) {
        self.id = UUID()
        self.symbol = symbol
        self.name = name
        self.coinGeckoId = coinGeckoId
        self.holdings = []
    }
}
```

- [ ] **Step 5: Verify package compiles**

Run: `cd Packages/PortuCore && swift build`
Expected: Build Succeeded

- [ ] **Step 6: Commit**

```bash
git add Packages/PortuCore/Sources/
git commit -m "feat: add SwiftData models (Portfolio, Account, Holding, Asset)"
```

---

### Task 4: KeychainService + SecretStore protocol

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Keychain/KeychainError.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Protocols/SecretStore.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Keychain/KeychainService.swift`

- [ ] **Step 1: Create KeychainError.swift**

```swift
import Foundation

public enum KeychainError: Error, Sendable {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case encodingFailed
}
```

- [ ] **Step 2: Create SecretStore.swift**

```swift
/// Protocol for secret storage, enabling mock injection in tests.
/// Key naming convention: "portu.<accountId>.<credentialType>"
/// Example: "portu.abc123.apiKey", "portu.abc123.apiSecret"
public protocol SecretStore: Sendable {
    func get(key: String) throws(KeychainError) -> String?
    func set(key: String, value: String) throws(KeychainError)
    func delete(key: String) throws(KeychainError)
}
```

- [ ] **Step 3: Create KeychainService.swift**

```swift
import Foundation
import Security

/// Wraps Security.framework Keychain APIs. Scoped by bundle ID (not sandboxed).
public struct KeychainService: SecretStore {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.portu.app") {
        self.service = service
    }

    public func get(key: String) throws(KeychainError) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8)
            else {
                throw .encodingFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw .unexpectedStatus(status)
        }
    }

    public func set(key: String, value: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else {
            throw .encodingFailed
        }

        // Delete existing item first (upsert pattern)
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw .unexpectedStatus(status)
        }
    }

    public func delete(key: String) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .unexpectedStatus(status)
        }
    }
}
```

- [ ] **Step 4: Verify package compiles**

Run: `cd Packages/PortuCore && swift build`
Expected: Build Succeeded

- [ ] **Step 5: Commit**

```bash
git add Packages/PortuCore/Sources/
git commit -m "feat: add KeychainService with SecretStore protocol"
```

---

### Task 5: PortuCore tests

**Files:**
- Create: `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`
- Create: `Packages/PortuCore/Tests/PortuCoreTests/KeychainServiceTests.swift`

Use Swift Testing (`@Test`, `#expect`) — not XCTest.

- [ ] **Step 1: Create ModelTests.swift**

```swift
import Testing
import SwiftData
@testable import PortuCore

@Suite("SwiftData Model Tests")
struct ModelTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Portfolio.self, Account.self, Holding.self, Asset.self,
            configurations: config
        )
        context = container.mainContext
    }

    @Test func portfolioCreation() throws {
        let portfolio = Portfolio(name: "Main")
        context.insert(portfolio)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Portfolio>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Main")
    }

    @Test func accountRelationship() throws {
        let portfolio = Portfolio(name: "Main")
        let account = Account(name: "Binance", kind: .exchange)
        account.exchangeType = .binance
        account.portfolio = portfolio
        portfolio.accounts.append(account)

        context.insert(portfolio)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Portfolio>())
        #expect(fetched.first?.accounts.count == 1)
        #expect(fetched.first?.accounts.first?.kind == .exchange)
        #expect(fetched.first?.accounts.first?.exchangeType == .binance)
    }

    @Test func holdingAssetRelationship() throws {
        let asset = Asset(symbol: "BTC", name: "Bitcoin", coinGeckoId: "bitcoin")
        let holding = Holding(amount: 1.5, costBasis: 60000)
        holding.asset = asset

        context.insert(asset)
        context.insert(holding)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Holding>())
        #expect(fetched.first?.asset?.symbol == "BTC")
        #expect(fetched.first?.amount == 1.5)
    }

    @Test func cascadeDeletePortfolioRemovesAccounts() throws {
        let portfolio = Portfolio(name: "Main")
        let account = Account(name: "Manual", kind: .manual)
        account.portfolio = portfolio
        portfolio.accounts.append(account)

        context.insert(portfolio)
        try context.save()

        context.delete(portfolio)
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.isEmpty)
    }

    @Test func accountKindPredicate() throws {
        let portfolio = Portfolio(name: "Main")
        let manual = Account(name: "Manual", kind: .manual)
        let exchange = Account(name: "Binance", kind: .exchange)
        manual.portfolio = portfolio
        exchange.portfolio = portfolio
        portfolio.accounts.append(contentsOf: [manual, exchange])

        context.insert(portfolio)
        try context.save()

        let predicate = #Predicate<Account> { $0.kind == .exchange }
        let descriptor = FetchDescriptor<Account>(predicate: predicate)
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.name == "Binance")
    }
}
```

- [ ] **Step 2: Create KeychainServiceTests.swift**

Tests use a `MockSecretStore` to test consumers without hitting real Keychain.

```swift
import Testing
@testable import PortuCore

/// In-memory mock for testing code that depends on SecretStore.
/// MainActor-isolated by default (via package setting), so Sendable is satisfied.
final class MockSecretStore: SecretStore {
    private var storage: [String: String] = [:]

    func get(key: String) throws(KeychainError) -> String? {
        storage[key]
    }

    func set(key: String, value: String) throws(KeychainError) {
        storage[key] = value
    }

    func delete(key: String) throws(KeychainError) {
        storage.removeValue(forKey: key)
    }
}

@Suite("SecretStore Tests")
struct SecretStoreTests {
    @Test func storeAndRetrieve() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.abc123.apiKey", value: "my-secret-key")
        let retrieved = try store.get(key: "portu.abc123.apiKey")
        #expect(retrieved == "my-secret-key")
    }

    @Test func retrieveNonExistent() throws {
        let store = MockSecretStore()
        let result = try store.get(key: "portu.missing.apiKey")
        #expect(result == nil)
    }

    @Test func deleteKey() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.abc123.apiKey", value: "secret")
        try store.delete(key: "portu.abc123.apiKey")
        let result = try store.get(key: "portu.abc123.apiKey")
        #expect(result == nil)
    }

    @Test func overwriteExistingKey() throws {
        let store = MockSecretStore()
        try store.set(key: "portu.abc123.apiKey", value: "old")
        try store.set(key: "portu.abc123.apiKey", value: "new")
        let result = try store.get(key: "portu.abc123.apiKey")
        #expect(result == "new")
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd Packages/PortuCore && swift test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Packages/PortuCore/Tests/
git commit -m "test: add PortuCore model and keychain tests"
```

---

## Chunk 2: PortuNetwork + PortuUI

### Task 6: PortuNetwork Package.swift + error types

**Files:**
- Create: `Packages/PortuNetwork/Package.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceServiceError.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortuNetwork",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortuNetwork", targets: ["PortuNetwork"]),
    ],
    dependencies: [
        .package(path: "../PortuCore"),
    ],
    targets: [
        .target(
            name: "PortuNetwork",
            dependencies: ["PortuCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "PortuNetworkTests",
            dependencies: ["PortuNetwork"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create PriceServiceError.swift**

```swift
import Foundation

public enum PriceServiceError: Error, Sendable {
    case rateLimited
    case networkUnavailable
    case decodingFailed
    case invalidResponse(statusCode: Int)
}
```

- [ ] **Step 3: Verify package compiles**

Run: `cd Packages/PortuNetwork && swift build`
Expected: Build Succeeded

- [ ] **Step 4: Commit**

```bash
git add Packages/PortuNetwork/
git commit -m "feat: add PortuNetwork package with error types"
```

---

### Task 7: PriceService stub + CoinGecko DTO

**Files:**
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/CoinGeckoDTO.swift`
- Create: `Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift`

- [ ] **Step 1: Create CoinGeckoDTO.swift**

CoinGecko `/simple/price` response format: `{"bitcoin":{"usd":62400.0},"ethereum":{"usd":3200.0}}`

```swift
import Foundation

/// Decodable type for CoinGecko /simple/price response.
/// Keys are coin IDs, values contain price in requested vs_currency.
nonisolated
struct CoinGeckoSimplePriceResponse: Sendable {
    let prices: [String: Decimal]

    init(from data: Data) throws(PriceServiceError) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: NSNumber]] else {
            throw .decodingFailed
        }
        var result: [String: Decimal] = [:]
        for (coinId, currencies) in json {
            if let usd = currencies["usd"] {
                result[coinId] = usd.decimalValue
            }
        }
        self.prices = result
    }
}
```

- [ ] **Step 2: Create PriceService.swift**

```swift
import Foundation
import PortuCore

/// Fetches and caches cryptocurrency prices from CoinGecko's free API.
/// Rate-limited to 10 requests/minute. Cache TTL: 30 seconds.
public final class PriceService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!
    private var cache: [String: Decimal] = [:]
    private var lastFetchDate: Date?
    private let cacheTTL: TimeInterval

    public init(session: URLSession = .shared, cacheTTL: TimeInterval = 30) {
        self.session = session
        self.cacheTTL = cacheTTL
    }

    /// Fetch current USD prices for the given CoinGecko coin IDs.
    /// Returns cached data if within TTL.
    public func fetchPrices(for coinIds: [String]) async throws(PriceServiceError) -> [String: Decimal] {
        if let lastFetch = lastFetchDate,
           Date.now.timeIntervalSince(lastFetch) < cacheTTL,
           !cache.isEmpty {
            return cache
        }

        let ids = coinIds.joined(separator: ",")
        let url = baseURL.appending(path: "simple/price")
            .appending(queryItems: [
                URLQueryItem(name: "ids", value: ids),
                URLQueryItem(name: "vs_currencies", value: "usd"),
            ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw .networkUnavailable
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 429: throw .rateLimited
            default: throw .invalidResponse(statusCode: http.statusCode)
            }
        }

        let parsed = try CoinGeckoSimplePriceResponse(from: data)
        cache = parsed.prices
        lastFetchDate = .now
        return parsed.prices
    }

    /// Clear the price cache, forcing a fresh fetch on next call.
    public func invalidateCache() {
        cache = [:]
        lastFetchDate = nil
    }
}
```

- [ ] **Step 3: Verify package compiles**

Run: `cd Packages/PortuNetwork && swift build`
Expected: Build Succeeded

- [ ] **Step 4: Commit**

```bash
git add Packages/PortuNetwork/Sources/
git commit -m "feat: add PriceService with CoinGecko client skeleton"
```

---

### Task 8: PortuNetwork tests

**Files:**
- Create: `Packages/PortuNetwork/Tests/PortuNetworkTests/PriceServiceTests.swift`

- [ ] **Step 1: Create PriceServiceTests.swift**

Tests use `URLProtocol` subclass to mock network responses.

```swift
import Testing
import Foundation
@testable import PortuNetwork

/// URLProtocol mock that returns a pre-configured response.
nonisolated
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockStatusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = Self.mockData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("PriceService Tests")
struct PriceServiceTests {
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    @Test func fetchPricesSuccess() async throws {
        let json = """
        {"bitcoin":{"usd":62400},"ethereum":{"usd":3200}}
        """
        MockURLProtocol.mockData = json.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = PriceService(session: session)
        let prices = try await service.fetchPrices(for: ["bitcoin", "ethereum"])

        #expect(prices["bitcoin"] == 62400)
        #expect(prices["ethereum"] == 3200)
    }

    @Test func fetchPricesRateLimited() async {
        MockURLProtocol.mockData = nil
        MockURLProtocol.mockStatusCode = 429

        let service = PriceService(session: session)
        await #expect(throws: PriceServiceError.rateLimited) {
            try await service.fetchPrices(for: ["bitcoin"])
        }
    }

    @Test func cacheReturnsCachedData() async throws {
        let json = """
        {"bitcoin":{"usd":62400}}
        """
        MockURLProtocol.mockData = json.data(using: .utf8)
        MockURLProtocol.mockStatusCode = 200

        let service = PriceService(session: session, cacheTTL: 60)

        // First fetch — hits network
        let first = try await service.fetchPrices(for: ["bitcoin"])
        #expect(first["bitcoin"] == 62400)

        // Change mock — but cache should still return old data
        MockURLProtocol.mockData = """
        {"bitcoin":{"usd":99999}}
        """.data(using: .utf8)

        let second = try await service.fetchPrices(for: ["bitcoin"])
        #expect(second["bitcoin"] == 62400) // cached
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd Packages/PortuNetwork && swift test`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add Packages/PortuNetwork/Tests/
git commit -m "test: add PriceService tests with URLProtocol mocking"
```

---

### Task 9: PortuUI Package

**Files:**
- Create: `Packages/PortuUI/Package.swift`
- Create: `Packages/PortuUI/Sources/PortuUI/Theme/PortuTheme.swift`
- Create: `Packages/PortuUI/Sources/PortuUI/Components/StatCard.swift`
- Create: `Packages/PortuUI/Sources/PortuUI/Components/CurrencyText.swift`
- Create: `Packages/PortuUI/Tests/PortuUITests/PortuUITests.swift`

PortuUI is model-agnostic — no dependency on PortuCore.

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortuUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortuUI", targets: ["PortuUI"]),
    ],
    targets: [
        .target(
            name: "PortuUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "PortuUITests",
            dependencies: ["PortuUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Create PortuTheme.swift**

```swift
import SwiftUI

public enum PortuTheme {
    public static let gainColor = Color.green
    public static let lossColor = Color.red
    public static let neutralColor = Color.secondary

    /// Returns gain/loss color based on a value being positive, negative, or zero.
    public static func changeColor(for value: Decimal) -> Color {
        if value > 0 { gainColor }
        else if value < 0 { lossColor }
        else { neutralColor }
    }
}
```

- [ ] **Step 3: Create StatCard.swift**

Generic stat card component — no domain model dependencies.
`StatCard` accepts `String` values intentionally: it is model-agnostic (PortuUI has no
PortuCore dependency), so it cannot accept `Decimal` + currency code directly. The caller
formats using `.formatted(.currency(code:))`. For inline currency display within domain
views, use `CurrencyText` which uses `Text(value, format: .currency(code:))` per spec.

```swift
import SwiftUI

/// A card displaying a labeled statistic value.
public struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?

    public init(title: String, value: String, subtitle: String? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}
```

- [ ] **Step 4: Create CurrencyText.swift**

```swift
import SwiftUI

/// Displays a Decimal value formatted as currency.
public struct CurrencyText: View {
    let value: Decimal
    let currencyCode: String

    public init(_ value: Decimal, currencyCode: String = "USD") {
        self.value = value
        self.currencyCode = currencyCode
    }

    public var body: some View {
        Text(value, format: .currency(code: currencyCode))
    }
}
```

- [ ] **Step 5: Create placeholder test**

```swift
import Testing
@testable import PortuUI

@Suite("PortuUI Tests")
struct PortuUITests {
    @Test func themeColors() {
        #expect(PortuTheme.changeColor(for: 1.0) == PortuTheme.gainColor)
        #expect(PortuTheme.changeColor(for: -1.0) == PortuTheme.lossColor)
        #expect(PortuTheme.changeColor(for: 0) == PortuTheme.neutralColor)
    }
}
```

- [ ] **Step 6: Verify and test**

Run: `cd Packages/PortuUI && swift test`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add Packages/PortuUI/
git commit -m "feat: add PortuUI package with theme, StatCard, CurrencyText"
```

---

## Chunk 3: App Target + Integration

### Task 10: XcodeGen project.yml + resources

**Files:**
- Create: `project.yml`
- Create: `Sources/Portu/Resources/Assets.xcassets/Contents.json`
- Create: `Sources/Portu/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `Sources/Portu/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Sources/Portu/Resources/Portu.entitlements`
- Create: `Sources/Portu/Resources/Info.plist`

- [ ] **Step 1: Create project.yml**

```yaml
name: Portu
options:
  bundleIdPrefix: com.portu
  deploymentTarget:
    macOS: "15.0"
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "6.2"
    MACOSX_DEPLOYMENT_TARGET: "15.0"
    SWIFT_STRICT_CONCURRENCY: complete

packages:
  PortuCore:
    path: Packages/PortuCore
  PortuNetwork:
    path: Packages/PortuNetwork
  PortuUI:
    path: Packages/PortuUI

targets:
  Portu:
    type: application
    platform: macOS
    sources:
      - path: Sources/Portu
        excludes:
          - Resources
    resources:
      - path: Sources/Portu/Resources/Assets.xcassets
    dependencies:
      - package: PortuCore
      - package: PortuNetwork
      - package: PortuUI
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.portu.app
        INFOPLIST_FILE: Sources/Portu/Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: Sources/Portu/Resources/Portu.entitlements
        CODE_SIGN_STYLE: Automatic
        OTHER_SWIFT_FLAGS: "-default-isolation MainActor"
    entitlements:
      path: Sources/Portu/Resources/Portu.entitlements

  PortuTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/PortuTests
    dependencies:
      - target: Portu
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.portu.app.tests
        OTHER_SWIFT_FLAGS: "-default-isolation MainActor"

schemes:
  Portu:
    build:
      targets:
        Portu: all
        PortuTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - PortuTests
    profile:
      config: Release
    analyze:
      config: Debug
    archive:
      config: Release
```

- [ ] **Step 2: Create Assets.xcassets/Contents.json**

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Create AccentColor.colorset/Contents.json**

```json
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 4: Create AppIcon.appiconset/Contents.json**

```json
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 5: Create Portu.entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 6: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Portu</string>
    <key>CFBundleDisplayName</key>
    <string>Portu</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
</dict>
</plist>
```

- [ ] **Step 7: Commit**

```bash
git add project.yml Sources/Portu/Resources/
git commit -m "feat: add XcodeGen project.yml and app resources"
```

---

### Task 11: PortuApp entry point + AppState

**Files:**
- Create: `Sources/Portu/App/AppState.swift`
- Create: `Sources/Portu/App/PortuApp.swift`

- [ ] **Step 1: Create AppState.swift**

```swift
import SwiftData

/// Root transient UI state. Does NOT hold SwiftData model arrays.
/// Views use @Query directly for SwiftData collections.
@Observable
final class AppState {
    var selectedSection: SidebarSection = .portfolio
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]
    var connectionStatus: ConnectionStatus = .idle
}

enum SidebarSection: Hashable, Sendable {
    case portfolio
    case account(PersistentIdentifier)
}

enum ConnectionStatus: Hashable, Sendable {
    case idle
    case fetching
    case error(String)
}
```

- [ ] **Step 2: Create PortuApp.swift**

```swift
import SwiftUI
import SwiftData
import PortuCore
import PortuNetwork
import PortuUI

@main
struct PortuApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(for: [
            Portfolio.self,
            Account.self,
            Holding.self,
            Asset.self,
        ])

        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(for: [
            Portfolio.self,
            Account.self,
            Holding.self,
            Asset.self,
        ])
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Portu/App/
git commit -m "feat: add PortuApp entry point and AppState"
```

---

### Task 12: Sidebar + ContentView shell

**Files:**
- Create: `Sources/Portu/Features/Sidebar/SidebarView.swift`

ContentView is the NavigationSplitView root that wires sidebar to detail.

- [ ] **Step 1: Create SidebarView.swift**

This file contains the ContentView (NavigationSplitView + StatusBar), SidebarView, and StatusBarView.

```swift
import SwiftUI
import SwiftData
import PortuCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $appState.selectedSection)
        } detail: {
            switch appState.selectedSection {
            case .portfolio:
                PortfolioView()
            case .account(let id):
                AccountDetailView(accountID: id)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    // TODO: Trigger price refresh
                }
            }
        }
    }
}

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            switch appState.connectionStatus {
            case .idle:
                Label("Idle", systemImage: "circle")
                    .foregroundStyle(.secondary)
            case .fetching:
                Label("Updating...", systemImage: "arrow.trianglehead.2.counterclockwise")
                    .foregroundStyle(.secondary)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            Spacer()

            if let lastUpdate = appState.lastPriceUpdate {
                Text("Updated \(lastUpdate, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("CoinGecko")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSection
    @Query private var portfolios: [Portfolio]
    @Query(sort: \Account.name) private var accounts: [Account]

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Portfolio", systemImage: "chart.pie")
                    .tag(SidebarSection.portfolio)
            }

            Section("Accounts") {
                if accounts.isEmpty {
                    Text("No accounts yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: iconForAccount(account))
                            .tag(SidebarSection.account(account.persistentModelID))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Portu")
        .toolbar {
            ToolbarItem {
                Button("Add Account", systemImage: "plus") {
                    // TODO: Add account flow
                }
            }
        }
    }

    private func iconForAccount(_ account: Account) -> String {
        switch account.kind {
        case .manual: "tray"
        case .exchange: "building.columns"
        case .wallet: "wallet.bifold"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Sidebar/
git commit -m "feat: add sidebar navigation with NavigationSplitView"
```

---

### Task 13: Portfolio summary view

**Files:**
- Create: `Sources/Portu/Features/Portfolio/PortfolioView.swift`

- [ ] **Step 1: Create PortfolioView.swift**

```swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct PortfolioView: View {
    @Environment(AppState.self) private var appState
    @Query private var holdings: [Holding]

    private var totalValue: Decimal {
        holdings.reduce(Decimal.zero) { sum, holding in
            let coinId = holding.asset?.coinGeckoId ?? ""
            let price = appState.prices[coinId] ?? 0
            return sum + holding.amount * price
        }
    }

    var body: some View {
        Group {
            if holdings.isEmpty {
                ContentUnavailableView {
                    Label("No Portfolio", systemImage: "chart.pie")
                } description: {
                    Text("Add an account or enter holdings manually to get started.")
                } actions: {
                    Button("Add Account") {
                        // TODO: Add account flow
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCards
                        holdingsList
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Portfolio")
    }

    @ViewBuilder
    private var summaryCards: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Total Value",
                value: totalValue.formatted(.currency(code: "USD"))
            )
            // P&L stub — directional icon pattern for accessibility
            // (real 24h change data will replace the placeholder)
            StatCard(
                title: "24h Change",
                value: "--",
                subtitle: "No price history yet"
            )
            .accessibilityLabel("24 hour change, no data available")
            StatCard(
                title: "Holdings",
                value: "\(holdings.count)"
            )
        }
    }

    /// Helper to create a P&L label with directional icon.
    /// Use when real 24h change data is available.
    /// Satisfies spec: "do not rely solely on green/red color for gain/loss"
    @ViewBuilder
    static func changeLabel(value: Decimal) -> some View {
        HStack(spacing: 2) {
            Image(systemName: value >= 0 ? "arrow.up" : "arrow.down")
            Text(value, format: .percent)
        }
        .foregroundStyle(PortuTheme.changeColor(for: value))
        .accessibilityLabel(
            "\(value >= 0 ? "up" : "down") \(abs(value).formatted(.percent))"
        )
    }

    @ViewBuilder
    private var holdingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Holdings")
                .font(.headline)

            ForEach(holdings) { holding in
                HoldingRow(holding: holding, price: appState.prices[holding.asset?.coinGeckoId ?? ""])
            }
        }
    }
}

/// Shared holding row — used in both PortfolioView and AccountDetailView.
/// Includes full VoiceOver accessibility label per spec requirements.
struct HoldingRow: View {
    let holding: Holding
    let price: Decimal?

    private var value: Decimal {
        holding.amount * (price ?? 0)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(holding.asset?.symbol ?? "???")
                    .font(.headline)
                Text(holding.asset?.name ?? "Unknown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                CurrencyText(value)
                Text("\(holding.amount.formatted()) \(holding.asset?.symbol ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(holding.asset?.name ?? "Unknown"), valued at \(value.formatted(.currency(code: "USD"))), amount \(holding.amount.formatted())"
        )
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/Portu/Features/Portfolio/
git commit -m "feat: add portfolio summary view with holdings list"
```

---

### Task 14: Account detail + Settings views

**Files:**
- Create: `Sources/Portu/Features/Accounts/AccountDetailView.swift`
- Create: `Sources/Portu/Features/Settings/SettingsView.swift`

- [ ] **Step 1: Create AccountDetailView.swift**

```swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct AccountDetailView: View {
    let accountID: PersistentIdentifier
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    private var account: Account? {
        modelContext.registeredModel(for: accountID)
    }

    var body: some View {
        Group {
            if let account {
                accountContent(account)
            } else {
                ContentUnavailableView(
                    "Account Not Found",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
    }

    @ViewBuilder
    private func accountContent(_ account: Account) -> some View {
        if account.holdings.isEmpty {
            ContentUnavailableView {
                Label("No Holdings", systemImage: "tray")
            } description: {
                Text("This account has no holdings yet.")
            } actions: {
                if account.kind == .exchange {
                    Button("Sync Account") {
                        // TODO: Sync from exchange
                    }
                }
            }
        } else {
            List(account.holdings) { holding in
                // Reuse the same HoldingRow from PortfolioView for consistent
                // accessibility labels and formatting
                HoldingRow(
                    holding: holding,
                    price: appState.prices[holding.asset?.coinGeckoId ?? ""]
                )
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem {
                if let lastSync = account.lastSyncedAt {
                    Text("Synced \(lastSync, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Create SettingsView.swift**

Standard macOS Settings scene (Cmd+comma).

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsTab()
            }
            Tab("Accounts", systemImage: "building.columns") {
                AccountsSettingsTab()
            }
        }
        .frame(width: 450, height: 300)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage("refreshInterval") private var refreshInterval = 30.0

    var body: some View {
        Form {
            Section("Price Updates") {
                Picker("Refresh interval", selection: $refreshInterval) {
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

private struct AccountsSettingsTab: View {
    var body: some View {
        Form {
            Section("Exchange API Keys") {
                Text("Configure exchange connections here.")
                    .foregroundStyle(.secondary)
                // TODO: API key management forms
            }

            Section("Wallet Addresses") {
                Text("Add wallet addresses for on-chain tracking.")
                    .foregroundStyle(.secondary)
                // TODO: Wallet address management
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Portu/Features/Accounts/ Sources/Portu/Features/Settings/
git commit -m "feat: add account detail view and settings scene"
```

---

### Task 15: Integration test + full build verification

**Files:**
- Create: `Tests/PortuTests/PortuAppTests.swift`

- [ ] **Step 1: Create PortuAppTests.swift**

```swift
import Testing

@Suite("Portu App Tests")
struct PortuAppTests {
    @Test func appLaunchesWithoutCrash() {
        // Placeholder — verifies the test target links correctly
        #expect(true)
    }
}
```

- [ ] **Step 2: Generate Xcode project**

Run: `xcodegen generate`
Expected: `⚙ Generating plists...` then `Created project at...`

- [ ] **Step 3: Build the project**

Run: `xcodebuild -scheme Portu -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

If build fails, fix issues and re-run. Common issues:
- Missing import statements
- SwiftData model issues (check `@Model` annotations)
- `@Query` outside of view (must be inside `View` struct)
- Concurrency issues with default MainActor isolation (add `nonisolated` where needed)

- [ ] **Step 4: Run SPM package tests**

Run: `cd Packages/PortuCore && swift test && cd ../PortuNetwork && swift test && cd ../PortuUI && swift test`
Expected: All tests pass

- [ ] **Step 5: Final commit**

```bash
git add Tests/
git commit -m "test: add app integration test placeholder"
```

- [ ] **Step 6: Tag the scaffolding milestone**

```bash
git add -A
git commit -m "feat: complete Portu SwiftUI app scaffolding" --allow-empty
```

---

## Parallel Execution Guide

For subagent-driven development, tasks can be parallelized as follows:

| Phase | Tasks | Dependencies |
|---|---|---|
| 1 — Infrastructure | Task 1 | None |
| 2 — SPM Packages (parallel) | Tasks 2-5 (PortuCore), Tasks 6-8 (PortuNetwork), Task 9 (PortuUI) | Task 1 |
| 3 — App Target (sequential) | Tasks 10-14 | Phase 2 complete |
| 4 — Integration | Task 15 | Phase 3 complete |

Tasks 2-5, 6-8, and 9 can run in **three parallel subagents** since the packages have no build-time dependencies on each other (PortuNetwork depends on PortuCore at the source level, but can be written in parallel — the build verification happens at integration in Task 15).
