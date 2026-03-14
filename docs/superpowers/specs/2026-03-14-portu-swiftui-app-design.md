# Portu — SwiftUI macOS Crypto Portfolio Dashboard

## Overview

Portu is a native macOS SwiftUI app for monitoring crypto portfolios. It aggregates holdings from manual entry, exchange API connections (Binance, Coinbase, Kraken, etc.), and on-chain wallet tracking into a single dashboard. 100% local-first — no backend server, no telemetry, no accounts.

## Requirements

- **Platform**: macOS 14.0+ (Sonoma)
- **Language**: Swift 6.x
- **UI Framework**: SwiftUI with AppKit bridges where needed
- **Build System**: XcodeGen (`project.yml`) + xcodebuild
- **Privacy**: All data local. Keychain for secrets, SwiftData for everything else. No cloud dependency.
- **Sandbox**: Not sandboxed (direct distribution, no Mac App Store). Keychain items scoped by bundle ID (`com.portu.app`).

## Architecture

### Project Structure

```
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

```
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

## Data Layer

### SwiftData Models (PortuCore)

```
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
├── portfolio: Portfolio           (back-reference, deleteRule: .nullify)

Holding
├── id: UUID
├── asset: Asset                   (many-to-one, deleteRule: .nullify)
├── amount: Decimal
├── costBasis: Decimal?            (per-unit cost, optional)
├── account: Account               (back-reference, deleteRule: .nullify)

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

### Supporting Types

```swift
// Flat enum — no associated values, safe for SwiftData predicates
enum AccountKind: String, Codable, CaseIterable {
    case manual, exchange, wallet
}

enum ExchangeType: String, Codable, CaseIterable {
    case binance, coinbase, kraken
}

enum Chain: String, Codable, CaseIterable {
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
    func get(key: String) throws -> String?
    func set(key: String, value: String) throws
    func delete(key: String) throws
}
```

`KeychainService` conforms to `SecretStore`. `PortuNetwork` depends on the protocol only — testable with a mock.

**Key naming convention**: `"portu.<accountId>.<credentialType>"` where credentialType is `apiKey`, `apiSecret`, or `passphrase`. Example: `"portu.abc123.apiKey"`, `"portu.abc123.apiSecret"`.

### Price Data (PortuNetwork)

`PriceService`:
- Fetches current prices from CoinGecko public API (no key required)
- Rate limiter: max 10 requests/minute (free tier safe)
- In-memory cache with configurable TTL (default 30s)
- Historical price data cached to `~/Library/Caches/Portu/` as JSON
- Publishes price updates via `AsyncThrowingStream<[String: Decimal], Error>` keyed by coinGeckoId
- Errors (rate limit, network failure) propagate through the stream; the app target catches them and updates `AppState.connectionStatus`

## UI Design

### Window Structure

`NavigationSplitView` with sidebar + detail:

```
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

### Settings Scene (Cmd+comma)

Separate window with tabs: Accounts (API keys, wallet addresses), Appearance, General (refresh interval).

### Design Tokens

- Sidebar: `.listStyle(.sidebar)` — automatic vibrancy
- Status bar: `.ultraThinMaterial` background
- Typography: system font (SF Pro), semantic styles (`.headline`, `.body`, `.caption`)
- Colors: semantic only (`Color.primary`, `.secondary`, `.accentColor`) — automatic dark mode
- Icons: SF Symbols exclusively
- Number formatting: `Decimal` with locale-aware currency formatting
- Animations: `withAnimation(.spring)` for state transitions

### State Management

```swift
@Observable
class AppState {
    var selectedSection: SidebarSection = .portfolio
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]     // coinGeckoId -> USD price
    var connectionStatus: ConnectionStatus = .idle
}

enum SidebarSection: Hashable {
    case portfolio
    case account(PersistentIdentifier)  // SwiftData stable ID, not Account reference
}

enum ConnectionStatus {
    case idle, fetching, error(String)
}
```

**Key design decisions:**
- `AppState` does NOT hold `portfolios` or any SwiftData model arrays. Views use `@Query` directly to observe SwiftData collections — this is the idiomatic pattern and avoids dual-source-of-truth.
- `AppState` only holds transient UI state (selection, prices, connection status).
- `SidebarSection.account` uses `PersistentIdentifier` (SwiftData's stable ID type), not a direct `Account` reference, to avoid reference-equality issues with `Hashable`.
- Settings uses the standard macOS `Settings { }` scene (Cmd+comma), not a sidebar section.

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
- macOS deployment target 14.0

### Scripts

- `scripts/generate.sh` — runs `xcodegen generate`, opens project
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
4. `KeychainService` with `SecretStore` protocol
5. Stub `PriceService` with CoinGecko client skeleton
6. Full UI shell: sidebar navigation, portfolio summary placeholder, settings placeholder
7. `AppState` with `@Observable`
8. Build scripts, `.gitignore`
9. The app compiles, launches, and shows the sidebar + detail layout with placeholder data

What the scaffolding does NOT include (future work):
- Actual exchange API integrations (Binance, Coinbase, Kraken clients)
- On-chain wallet tracking (RPC calls)
- Real chart rendering (will need Swift Charts or a charting library)
- Auto-refresh timer
- Sparkle auto-updates
- Notarization / distribution pipeline
