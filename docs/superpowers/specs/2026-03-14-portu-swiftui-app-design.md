# Portu — SwiftUI macOS Crypto Portfolio Dashboard

## Overview

Portu is a native macOS SwiftUI app for monitoring crypto portfolios. It aggregates holdings from manual entry, exchange API connections (Binance, Coinbase, Kraken, etc.), and on-chain wallet tracking into a single dashboard. 100% local-first — no backend server, no telemetry, no accounts.

## Requirements

- **Platform**: macOS 15.0+ (Sequoia)
- **Language**: Swift 6.2+
- **UI Framework**: SwiftUI with AppKit bridges where needed
- **Concurrency**: Default Main Actor isolation via `SwiftSetting.defaultIsolation(.MainActor)` in all targets
- **Build System**: XcodeGen (`project.yml`) + xcodebuild
- **Privacy**: All data local. Keychain for secrets, SwiftData for everything else. No cloud dependency.
- **Sandbox**: Not sandboxed (direct distribution, no Mac App Store). Keychain items scoped by bundle ID (`com.portu.app`).

## Architecture

### Concurrency Model

All SPM package targets and the app target set default Main Actor isolation:

```swift
// In each Package.swift target:
swiftSettings: [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self)
]
```

This means all types are `@MainActor` by default. Use `nonisolated` to opt out where needed (e.g., pure data transforms, network parsing). This eliminates boilerplate `@MainActor` annotations and makes concurrency violations a compile error.

### Project Structure

```text
Portu/
├── project.yml                     # XcodeGen configuration
├── Packages/
│   ├── PortuCore/                  # Models, Keychain, shared types
│   │   ├── Package.swift
│   │   ├── Sources/
│   │   │   ├── Models/             # SwiftData models
│   │   │   ├── Keychain/           # KeychainService
│   │   │   └── Protocols/          # SecretStore, etc.
│   │   └── Tests/
│   ├── PortuNetwork/               # Exchange APIs, price feeds, on-chain
│   │   ├── Package.swift
│   │   ├── Sources/
│   │   │   ├── PriceService/       # CoinGecko client + cache
│   │   │   ├── ExchangeClients/    # Binance, Coinbase, etc.
│   │   │   └── OnChain/            # Wallet/RPC tracking
│   │   └── Tests/
│   └── PortuUI/                    # Reusable UI components
│       ├── Package.swift
│       ├── Sources/
│       │   ├── Charts/             # Allocation chart, price sparklines
│       │   ├── Components/         # Styled cards, badges, formatters
│       │   └── Theme/              # Colors, typography tokens
│       └── Tests/
├── Sources/
│   └── Portu/                      # App target (composition root)
│       ├── App/
│       │   ├── PortuApp.swift      # @main, scene definitions
│       │   └── AppState.swift      # Root @Observable state
│       ├── Features/
│       │   ├── Portfolio/          # Portfolio summary view + viewmodel
│       │   ├── Accounts/           # Account list, detail, add flows
│       │   ├── Sidebar/            # Sidebar navigation
│       │   └── Settings/           # Settings view
│       └── Resources/
│           ├── Assets.xcassets
│           ├── Portu.entitlements
│           └── Info.plist
├── Tests/
│   └── PortuTests/
├── scripts/
│   ├── generate.sh                 # xcodegen generate wrapper
│   └── build.sh                    # xcodebuild wrapper
└── .gitignore                      # Ignores .xcodeproj, DerivedData, etc.
```

### Module Dependency Graph

```text
PortuApp (app target)
├── PortuCore
├── PortuNetwork → PortuCore
└── PortuUI              (no domain dependencies — model-agnostic)
```

- `PortuCore` depends on nothing (Foundation, Security, SwiftData only)
- `PortuNetwork` depends on `PortuCore` for model types
- `PortuUI` has no domain dependencies — it is model-agnostic (charts accept generic data, not `Holding`/`Asset` types). The app target bridges domain models to UI components.
- `PortuNetwork` and `PortuUI` never depend on each other
- The app target is the only place all three packages are imported together

### Domain View Models

Domain-specific view models live in `Sources/Portu/Features/`, not in `PortuUI`. Each feature folder (Portfolio, Accounts, etc.) contains its own view model that bridges `PortuCore` models to `PortuUI` components. `PortuUI` never imports domain types — the app target is the bridge layer.

## Data Layer

### SwiftData Models (PortuCore)

```text
Portfolio
├── id: UUID
├── name: String
├── accounts: [Account]           (1-to-many, deleteRule: .cascade)
├── createdAt: Date

Account
├── id: UUID
├── name: String
├── kind: AccountKind              (.manual, .exchange, .wallet)
├── exchangeType: ExchangeType?    (set when kind == .exchange)
├── chain: Chain?                  (set when kind == .wallet)
├── holdings: [Holding]            (1-to-many, deleteRule: .cascade)
├── lastSyncedAt: Date?
├── portfolio: Portfolio?          (back-reference, deleteRule: .nullify)

Holding
├── id: UUID
├── asset: Asset?                  (many-to-one, deleteRule: .nullify)
├── amount: Decimal
├── costBasis: Decimal?            (per-unit cost, optional)
├── account: Account?              (back-reference, deleteRule: .nullify)

Asset
├── id: UUID
├── symbol: String                 (e.g., "BTC")
├── name: String                   (e.g., "Bitcoin")
├── coinGeckoId: String            (for price lookups)
├── chain: Chain?                  (for on-chain assets)
├── contractAddress: String?       (for tokens)
├── holdings: [Holding]            (back-reference, deleteRule: .nullify)
Note: Assets are never cascade-deleted. They are shared reference data.
Orphaned assets (no holdings) can be cleaned up periodically.
```

**Important:** All relationships with `.nullify` delete rules are optional. When a parent is deleted, SwiftData sets the inverse to `nil` — a non-optional property would crash at runtime.

### Supporting Types

```swift
// Flat enum — no associated values, safe for SwiftData predicates
enum AccountKind: String, Codable, CaseIterable, Sendable {
    case manual, exchange, wallet
}

enum ExchangeType: String, Codable, CaseIterable, Sendable {
    case binance, coinbase, kraken
}

enum Chain: String, Codable, CaseIterable, Sendable {
    case ethereum, solana, bitcoin
}
```

Note: `AccountKind` is deliberately flat (no associated values) because SwiftData
predicates cannot match on enum associated values. The `exchangeType` and `chain`
properties on `Account` are optional and contextually required based on `kind`.

### Secrets (Keychain)

`KeychainService` in `PortuCore` wraps `Security.framework`:
- Store/retrieve/delete by key string
- Scoped by bundle ID (`com.portu.app`) — no explicit Keychain access group needed since the app is not sandboxed

`SecretStore` protocol defined in `PortuCore`:
```swift
protocol SecretStore: Sendable {
    func get(key: String) throws(KeychainError) -> String?
    func set(key: String, value: String) throws(KeychainError)
    func delete(key: String) throws(KeychainError)
}

enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}
```

`KeychainService` conforms to `SecretStore`. `PortuNetwork` depends on the protocol only — testable with a mock. Keychain operations are synchronous; no async needed.

**Key naming convention**: `"portu.<accountId>.<credentialType>"` where credentialType is `apiKey`, `apiSecret`, or `passphrase`. Example: `"portu.abc123.apiKey"`, `"portu.abc123.apiSecret"`.

### Price Data (PortuNetwork)

`PriceService`:
- Fetches current prices from CoinGecko public API (no key required)
- Rate limiter: max 10 requests/minute (free tier safe)
- In-memory cache with configurable TTL (default 30s)
- Historical price data cached to `~/Library/Caches/Portu/` as JSON (use `URL.cachesDirectory.appending(path: "Portu")`)
- Publishes price updates via `AsyncThrowingStream<[String: Decimal], any Error>` keyed by coinGeckoId
- Transient errors (rate limit, network unavailable) are silently retried on the next poll tick; non-transient errors (decoding, invalid response) terminate the stream

```swift
enum PriceServiceError: Error, Sendable {
    case rateLimited
    case networkUnavailable
    case decodingFailed
    case invalidResponse(statusCode: Int)
}
```

## UI Design

### Window Structure

`NavigationSplitView` with sidebar + detail:

```text
┌──────────────────────────────────────────────────────────┐
│  Toolbar: [Refresh] [+ Add Account]                      │
├───────────────┬──────────────────────────────────────────┤
│  SIDEBAR      │  DETAIL                                  │
│               │                                          │
│  Portfolio    │  Total Value / P&L / Allocation Chart    │
│  Accounts     │  Holdings List (sorted by value)         │
│    Binance    │                                          │
│    0xabc...   │                                          │
│    Manual     │                                          │
│               │                                          │
│               │                                          │
├───────────────┴──────────────────────────────────────────┤
│  Status: Last updated 2s ago              CoinGecko      │
└──────────────────────────────────────────────────────────┘
Settings: Cmd+comma (separate window, standard macOS pattern)
```

### Sidebar Sections

- **Portfolio** — default selection, shows aggregated summary
- **Accounts** — expandable section listing each account; click for individual account detail

Settings is NOT in the sidebar. It uses the standard macOS `Settings { }` scene,
accessible via Cmd+comma or the app menu. This follows macOS conventions.

### Detail Views

| Sidebar Selection | Detail Content |
|---|---|
| Portfolio | Total value, 24h change, allocation donut chart, all holdings list |
| Account (specific) | Account holdings, sync status, last synced timestamp |

### Empty States

Use `ContentUnavailableView` for all empty/error states:

| State | Presentation |
|---|---|
| No portfolios yet | `ContentUnavailableView("No Portfolio", systemImage: "chart.pie", description: ...)` with action button to create one |
| Account has no holdings | `ContentUnavailableView` with sync or manual-add action |
| Price fetch failed | `ContentUnavailableView` with retry action |

### Settings Scene (Cmd+comma)

Separate window with tabs: Accounts (API keys, wallet addresses), Appearance, General (refresh interval).

### Design Tokens

- Sidebar: `.listStyle(.sidebar)` — automatic vibrancy
- Status bar: `.ultraThinMaterial` background
- Typography: system font (SF Pro), semantic styles (`.headline`, `.body`, `.caption`)
- Colors: semantic only (`Color.primary`, `.secondary`, `.accentColor`) — automatic dark mode
- Icons: SF Symbols exclusively
- Number formatting: use `Text(value, format: .currency(code: "USD"))` and `Text(value, format: .percent)` — never manual `NumberFormatter` or `String(format:)`
- Animations: `withAnimation(.spring) { ... }` for state transitions; any `.animation()` modifier must include a `value:` parameter

### Accessibility

- **Toolbar buttons** must always include text labels: `Button("Refresh", systemImage: "arrow.clockwise", action: refresh)`, not icon-only buttons
- **Dynamic Type**: use semantic font styles exclusively (`.headline`, `.body`, etc.) — never hardcode font sizes
- **Reduce Motion**: check `accessibilityReduceMotion` environment value; replace spring animations with `.opacity` transitions when enabled
- **P&L indicators**: do not rely solely on green/red color for gain/loss — include directional icons (SF Symbols `arrow.up`/`arrow.down`) or text labels for `accessibilityDifferentiateWithoutColor` support
- **Financial data VoiceOver**: price values and percentage changes should have clear `accessibilityLabel` values (e.g., "Bitcoin, up 3.2 percent, valued at $42,000")
- **Menus**: always include text with icons: `Menu("Options", systemImage: "ellipsis.circle") { ... }`

### State Management

```swift
@Observable
class AppState {
    var selectedSection: SidebarSection = .portfolio
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]     // coinGeckoId -> USD price
    var connectionStatus: ConnectionStatus = .idle
}

enum SidebarSection: Hashable, Sendable {
    case portfolio
    case account(PersistentIdentifier)  // SwiftData stable ID, not Account reference
}

enum ConnectionStatus: Hashable, Sendable {
    case idle, fetching, error(String)
}
```

**Key design decisions:**
- `AppState` does NOT hold `portfolios` or any SwiftData model arrays. Views use `@Query` directly to observe SwiftData collections — this is the idiomatic pattern and avoids dual-source-of-truth.
- `AppState` only holds transient UI state (selection, prices, connection status).
- `SidebarSection.account` uses `PersistentIdentifier` (SwiftData's stable ID type), not a direct `Account` reference, to avoid reference-equality issues with `Hashable`.
- Settings uses the standard macOS `Settings { }` scene (Cmd+comma), not a sidebar section.
- `AppState` is `@MainActor` by default (via `defaultIsolation`), so no explicit annotation needed.
- `ConnectionStatus` conforms to `Hashable` to support `.animation(.default, value: connectionStatus)`.

`ModelContainer` is configured in `PortuApp.swift` with the schema `[Portfolio.self, Account.self, Holding.self, Asset.self]` using the default store location. Migration strategy deferred to future work.

Injected via `.environment()` at the app root (both `AppState` and `ModelContainer`).

## Network Privacy Model

| What | Where | Direction |
|---|---|---|
| Portfolio data, holdings, preferences | Local (SwiftData) | Never leaves device |
| API keys, secrets | macOS Keychain | Never leaves device |
| Price cache | Local disk (~/Library/Caches/) | Never leaves device |
| Price fetches | CoinGecko public API | Outbound only, no user ID |
| Exchange sync | Direct to exchange API | Outbound only, your API keys |
| On-chain reads | Public RPC nodes | Outbound only, public data |
| Telemetry, analytics | None | Does not exist |

## Build & Tooling

### XcodeGen

`project.yml` defines:
- App target (`Portu`) with sources, resources, entitlements
- Local package dependencies (PortuCore, PortuNetwork, PortuUI)
- Debug and Release configurations
- macOS deployment target 15.0

### Scripts

- `scripts/generate.sh` — runs `xcodegen generate`
- `scripts/build.sh` — `xcodebuild -scheme Portu -configuration Release build`

### .gitignore

Ignore `.xcodeproj` (generated), `DerivedData/`, `.build/`, `*.xcuserdata`.

## Testing Strategy

- **PortuCore**: unit tests for models, Keychain wrapper (with mock Keychain in tests)
- **PortuNetwork**: unit tests for API parsing, rate limiter, cache; mock `SecretStore` and `URLProtocol` for network mocking
- **PortuUI**: snapshot tests for key components (future, not in scaffolding)
- **App target**: integration tests wiring real packages together (future)

## Scaffolding Scope

The initial scaffolding delivers:

1. Complete project structure with all three SPM packages
2. XcodeGen `project.yml` that builds and runs
3. SwiftData models (Portfolio, Account, Holding, Asset)
4. `KeychainService` with `SecretStore` protocol and typed `KeychainError`
5. Stub `PriceService` with CoinGecko client skeleton and typed `PriceServiceError`
6. Full UI shell: sidebar navigation, portfolio summary placeholder, settings placeholder
7. `ContentUnavailableView` for empty states
8. `AppState` with `@Observable`
9. Default Main Actor isolation configured in all targets
10. Build scripts, `.gitignore`
11. The app compiles, launches, and shows the sidebar + detail layout with placeholder data

What the scaffolding does NOT include (future work):
- Actual exchange API integrations (Binance, Coinbase, Kraken clients)
- On-chain wallet tracking (RPC calls)
- Real chart rendering (will need Swift Charts or a charting library)
- Auto-refresh timer
- Sparkle auto-updates
- Notarization / distribution pipeline
