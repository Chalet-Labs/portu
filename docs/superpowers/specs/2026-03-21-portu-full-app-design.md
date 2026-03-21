# Portu — Full App Design Spec

## Overview

Portu is a native macOS SwiftUI crypto portfolio dashboard. It aggregates holdings from multiple data sources — DeBank, Zapper, exchange APIs, direct RPC, and manual entry — into a unified local-first interface. No backend server, no telemetry, no accounts.

This spec defines the complete application: data model, API layer, sync engine, navigation, and all 7 views. It supersedes the original scaffolding spec (`2026-03-14-portu-swiftui-app-design.md`).

## Requirements

- **Platform**: macOS 15.0+ (Sequoia)
- **Language**: Swift 6.2+
- **UI Framework**: SwiftUI with Swift Charts for all charting
- **Persistence**: SwiftData (local), Keychain (secrets)
- **Concurrency**: Default Main Actor isolation via `defaultIsolation(MainActor.self)`
- **Build System**: XcodeGen (`project.yml`) + xcodebuild
- **Privacy**: All data local. No cloud. No telemetry.
- **Appearance**: Dark theme default, light mode support deferred to future work

## Architecture

### System Architecture

```
External Sources → PortuNetwork → PortuCore → App Views
```

**External Sources** (network boundary):
- DeBank API — DeFi positions, token balances
- Zapper API — DeFi positions, token balances
- Exchange APIs — Kraken, Binance, Coinbase balances
- RPC Nodes — direct on-chain balance queries
- CoinGecko — price feeds, market data, historical prices

**PortuNetwork** package:
- `PortfolioDataProvider` protocol — source-agnostic abstraction, returns **plain Sendable DTOs** (not SwiftData models)
- `DeBankProvider`, `ZapperProvider`, `RPCProvider`, `ExchangeProvider` — concrete implementations
- `PriceService` — CoinGecko price cache + polling
- No SwiftData dependency — this package knows nothing about persistence

**PortuCore** package:
- SwiftData `@Model` types (Account, Position, PositionToken, Asset, etc.)
- Sync DTOs (`PositionDTO`, `TokenDTO`, `AssetDTO`) — plain `Sendable` structs used as the transport format between PortuNetwork and the persistence layer
- `SyncContext` — account-scoped request DTO
- `KeychainService` — API keys, secrets
- `SnapshotStore` — historical portfolio value time series

**App target** (Sources/Portu):
- SwiftUI views organized by feature
- `AppState` — transient UI state (prices, selection, connection status)
- `SyncEngine` — orchestrates sync: calls providers (gets DTOs), maps DTOs → SwiftData models on the correct `ModelContext`, creates snapshots. Lives here because it bridges PortuNetwork and SwiftData persistence.
- Feature view models bridging PortuCore models to PortuUI components

**PortuUI** package:
- Model-agnostic reusable UI components, theme, charts

### Module Dependency Graph

```
PortuApp (app target)
├── PortuCore         (Foundation, Security, SwiftData)
├── PortuNetwork      → PortuCore (for DTOs and SyncContext only — no SwiftData types)
└── PortuUI           (no domain dependencies)
```

**Key boundary rule:** `@Model` objects never cross async/module boundaries. PortuNetwork
returns DTOs. SyncEngine (app target) is the only place that touches both DTOs and
`ModelContext`. All SwiftData writes happen on a single context/actor.

### Sync Model

**Sync-on-demand** (MVP): User clicks "Sync" → SyncEngine fetches all sources → writes to SwiftData → views reactively update via `@Query`. Auto-sync with configurable intervals is deferred to future work.

SyncEngine flow (runs in app target, has access to `ModelContext`):
1. For each active Account where `dataSource != .manual`:
   a. Construct `SyncContext` from Account @Model (reading properties on the current actor)
   b. Resolve `PortfolioDataProvider` based on `dataSource`
2. Call `fetchBalances(context:)` → returns `[PositionDTO]` (plain structs, no SwiftData)
3. Call `fetchDeFiPositions(context:)` → returns `[PositionDTO]` (empty if unsupported)
4. **Map DTOs → SwiftData** on the `ModelContext`:
   a. Upsert `Asset` @Model records from `TokenDTO` fields
   b. Delete stale `Position` records from previous sync for that account
   c. Create new `Position` and `PositionToken` @Model instances from DTOs
   d. Link PositionTokens to upserted Assets
   e. `context.save()`
5. Create AssetSnapshot records (one per asset per account from the synced positions)
6. After all accounts are synced: create PortfolioSnapshot (aggregated totals) and AccountSnapshot (per-account totals)
7. Prune old snapshots (all three tiers: Portfolio, Account, Asset)
8. Update `Account.lastSyncedAt`

**Error handling**: SyncEngine syncs accounts independently. If one account's provider fails:
- The error is recorded on that account (`Account.lastSyncError: String?`)
- Existing positions for that account are preserved (not deleted)
- Sync continues with remaining accounts
- Snapshots reflect whatever data was successfully fetched
- `SyncStatus.error` shows a summary of failed accounts
- User can retry individual accounts or all failed accounts

## Data Model

### Source-Agnostic Design

The data model is not coupled to any specific provider. All protocol-specific fields are optional. The `PortfolioDataProvider` protocol abstracts data sources — DeBank, Zapper, RPC, and exchange clients all conform to it. Features degrade gracefully when a less-rich provider is used:

| Feature | DeBank | Zapper | RPC | Exchange |
|---|---|---|---|---|
| Token balances | ✓ | ✓ | ✓ | ✓ |
| DeFi positions | ✓ | ✓ | — | — |
| Health factors | ✓ | partial | — | — |
| Protocol grouping | ✓ | ✓ | — | — |

UI hides unsupported features rather than showing broken/empty data. Each provider declares its capabilities via `ProviderCapabilities`.

### SwiftData Models

```
Account
├── id: UUID
├── name: String
├── kind: AccountKind              (.wallet, .exchange, .manual)
├── exchangeType: ExchangeType?    (set when kind == .exchange)
├── dataSource: DataSource         (.debank, .zapper, .rpc, .exchange, .manual)
├── addresses: [WalletAddress]     (1:N, cascade delete)
├── positions: [Position]          (1:N, cascade delete)
├── group: String?
├── notes: String?
├── lastSyncedAt: Date?
├── lastSyncError: String?         (nil = no error; set on failed sync, cleared on success)
├── isActive: Bool

WalletAddress
├── id: UUID
├── chain: Chain?                  (nil = EVM address, provider queries all EVM chains)
├── address: String
├── account: Account?              (back-reference, nullify)
Note: One 0x address is valid on all EVM chains simultaneously. When chain is nil,
the provider (DeBank/Zapper) fetches across all supported EVM chains automatically.
When chain is set (e.g., .solana), it restricts to that chain. Users create ONE
WalletAddress per 0x address, not one per chain.

Position                            — the core entity
├── id: UUID
├── positionType: PositionType     (.idle, .lending, .liquidityPool, .staking, .farming, .vesting, .other)
├── chain: Chain
├── protocolId: String?            (DeBank/Zapper protocol identifier)
├── protocolName: String?
├── protocolLogoURL: String?
├── healthFactor: Double?          (lending positions only)
├── netUSDValue: Decimal           (supply positive, borrow negative; for lending = supply - borrow)
├── tokens: [PositionToken]        (1:N, cascade delete)
├── account: Account?              (back-reference, nullify)
├── syncedAt: Date

PositionToken                       — bridges Position ↔ Asset
├── id: UUID
├── role: TokenRole                (.supply, .borrow, .reward, .stake, .lpToken, .balance)
├── amount: Decimal
├── usdValue: Decimal
├── asset: Asset?                  (N:1, nullify — assets are shared reference data)
├── position: Position?            (back-reference, nullify)

Asset                               — shared reference data, never cascade-deleted
├── id: UUID
├── symbol: String                 (e.g., "ETH", "WBTC")
├── name: String                   (e.g., "Ethereum")
├── chain: Chain?                  (nil = multi-chain asset)
├── contractAddress: String?
├── debankId: String?
├── coinGeckoId: String?
├── logoURL: String?
├── category: AssetCategory        (.major, .stablecoin, .defi, .meme, .privacy, .governance, .other)
├── isVerified: Bool

PortfolioSnapshot                   — append-only time series for Performance view
├── id: UUID
├── timestamp: Date
├── totalValue: Decimal
├── idleValue: Decimal
├── deployedValue: Decimal
├── debtValue: Decimal

AccountSnapshot                     — per-account time series for account-filtered Performance
├── id: UUID
├── timestamp: Date
├── accountId: UUID                (not a relationship — survives account deletion for historical data)
├── totalValue: Decimal

AssetSnapshot                       — per-asset per-account time series
├── id: UUID
├── timestamp: Date
├── accountId: UUID                (not a relationship — survives deletion)
├── assetId: UUID                  (not a relationship — survives deletion)
├── symbol: String                 (denormalized for display — survives Asset changes)
├── category: AssetCategory        (denormalized — enables category grouping without joins)
├── amount: Decimal                (token quantity at sync time)
├── usdValue: Decimal              (USD value at sync time)
```

AssetSnapshot enables:
- **Performance "Assets" mode** — group by `category`, sum `usdValue`, chart over time as stacked AreaMark
- **Performance account filter + category breakdown** — filter by `accountId`, then group by `category`
- **Asset Detail "$ Value" mode** — filter by `assetId`, chart `usdValue` over time
- **Asset Detail "Amount" mode** — filter by `assetId`, chart `amount` over time
- **Asset categories bottom panel** — compare start/end `usdValue` for period % change

Storage estimate: ~2.5 MB/year for 50 assets × 15 accounts × 2 syncs/day with pruning.
Same pruning rules as PortfolioSnapshot apply to AssetSnapshot.

**Key design decisions:**
- **No Portfolio model** — single-portfolio MVP. Account is the top-level entity. Multi-portfolio support can be added later by introducing a Portfolio parent.
- **Position is the core entity** — each DeFi position, staking position, LP position, or idle wallet balance is a Position.
- **Protocol is denormalized** — protocolId/Name/LogoURL live directly on Position. Avoids relationship complexity.
- **Prices live in AppState, not on Asset** — current prices are transient (from PriceService cache). No stale price problem.
- **Snapshots use UUID keys, not relationships** — historical data survives account/asset deletion. `symbol` and `category` are denormalized on AssetSnapshot so charts display correctly even if the Asset record changes.
- **Three snapshot tiers** — PortfolioSnapshot (fast total-value queries), AccountSnapshot (account-filtered totals), AssetSnapshot (category/asset drill-downs). All created on each sync.
- **SwiftData migration** — the existing Portfolio model and old schema are replaced entirely. Use destructive migration (wipe and recreate) since the app has no real user data yet — only scaffolding test data.

### Price Display Rules

Prices come from two sources. The rules for which to use:

1. **Live price** (`AppState.prices[asset.coinGeckoId]`) — used when `coinGeckoId` is present and PriceService has a cached value. This is the authoritative price for display.
2. **Sync-time price** (`PositionToken.usdValue / PositionToken.amount`) — used as fallback when the asset has no `coinGeckoId` (obscure DeFi tokens). Displayed with a "stale" indicator showing sync time.

For "Value" columns: `amount * livePrice` when live price is available, otherwise `PositionToken.usdValue` from sync.

For "24h change" in the Overview top bar: computed as `sum(amount * price * priceChange24hPercent)` for each asset with a `coinGeckoId`. Assets without `coinGeckoId` contribute $0 to the 24h change (shown as approximate with a tooltip).

### Net Amount Aggregation

"Net Amount" in the All Assets table = sum of all PositionToken amounts for that Asset across all accounts and positions. Tokens with role `.borrow` subtract from the total. Tokens with role `.reward` are excluded (unclaimed rewards). This gives net exposure per asset.

### Manual Entry

Manual accounts (`kind == .manual`, `dataSource == .manual`) do not use `PortfolioDataProvider`. Instead:
- User creates positions directly via the "Add position" form in All Positions view
- Form fields: Asset (search/select or create new), Amount, Position Type, optional Protocol name, optional USD value override
- Manual positions persist across syncs — SyncEngine skips accounts with `dataSource == .manual`
- Manual positions can be edited and deleted inline

### Supporting Types

```swift
enum AccountKind: String, Codable, CaseIterable, Sendable {
    case wallet, exchange, manual
}

enum DataSource: String, Codable, CaseIterable, Sendable {
    case debank, zapper, rpc, exchange, manual
}

enum ExchangeType: String, Codable, CaseIterable, Sendable {
    case binance, coinbase, kraken
}

enum Chain: String, Codable, CaseIterable, Sendable {
    case ethereum, polygon, arbitrum, optimism, base, bsc, solana, bitcoin, avalanche, monad, katana
}

enum PositionType: String, Codable, CaseIterable, Sendable {
    case idle, lending, liquidityPool, staking, farming, vesting, other
}

enum TokenRole: String, Codable, CaseIterable, Sendable {
    case supply, borrow, reward, stake, lpToken, balance
}

enum AssetCategory: String, Codable, CaseIterable, Sendable {
    case major, stablecoin, defi, meme, privacy, fiat, governance, other
}
```

Note: `logoURL` and `protocolLogoURL` are `String?` rather than `URL?` because SwiftData
does not natively support `URL` storage in predicates. Convert to `URL` at the view layer.

```swift
// (continued)
```

## API Layer

### PortfolioDataProvider Protocol

The protocol is **account-scoped** via `SyncContext` and returns **plain Sendable DTOs**,
not SwiftData `@Model` objects. This keeps the network layer free of persistence concerns
and ensures safe transfer across async/actor boundaries.

```swift
// ── SyncContext (lives in PortuCore) ──────────────────────────────
/// Lightweight DTO constructed by SyncEngine from an Account @Model.
struct SyncContext: Sendable {
    let accountId: UUID
    let kind: AccountKind
    let addresses: [(address: String, chain: Chain?)]  // from WalletAddress records
    let exchangeType: ExchangeType?                     // set when kind == .exchange
}

// ── Transport DTOs (live in PortuCore) ───────────────────────────
/// Plain structs returned by providers. SyncEngine maps these to @Model objects.
struct PositionDTO: Sendable {
    let positionType: PositionType
    let chain: Chain
    let protocolId: String?
    let protocolName: String?
    let protocolLogoURL: String?
    let healthFactor: Double?
    let netUSDValue: Decimal
    let tokens: [TokenDTO]
}

struct TokenDTO: Sendable {
    let role: TokenRole
    let symbol: String
    let name: String
    let amount: Decimal
    let usdValue: Decimal
    let chain: Chain?
    let contractAddress: String?
    let debankId: String?
    let coinGeckoId: String?
    let logoURL: String?
    let category: AssetCategory
    let isVerified: Bool
}

// ── Protocol (lives in PortuNetwork) ─────────────────────────────
protocol PortfolioDataProvider: Sendable {
    var capabilities: ProviderCapabilities { get }
    func fetchBalances(context: SyncContext) async throws -> [PositionDTO]
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO]
}

extension PortfolioDataProvider {
    func fetchDeFiPositions(context: SyncContext) async throws -> [PositionDTO] { [] }
}

struct ProviderCapabilities: Sendable {
    var supportsTokenBalances: Bool  // always true
    var supportsDeFiPositions: Bool
    var supportsHealthFactors: Bool
}
```

**SyncEngine mapping** (app target): receives `[PositionDTO]` from providers, then on
the correct `ModelContext`:
1. Upserts `Asset` records from `TokenDTO` fields (deduplicated by symbol + chain + contractAddress)
2. Creates `Position` @Model instances from `PositionDTO`
3. Creates `PositionToken` @Model instances from `TokenDTO`, linking to upserted Assets
4. All writes happen in a single `ModelContext.save()` call per account

### Provider Implementations

Each provider uses `SyncContext` differently:

- **ZapperProvider** — iterates `context.addresses`, calls Zapper API for each address across all chains (or specific chain if `address.chain` is set). Merges results. User provides API key (stored as `"portu.provider.zapper.apiKey"`).
- **DeBankProvider** — same pattern as Zapper. Uses DeBank Cloud API. User provides API key.
- **RPCProvider** — iterates `context.addresses`, queries ERC-20 balances via `eth_call` per chain. Uses `address.chain` to select the right RPC endpoint. User provides RPC endpoint URLs per chain (stored in SwiftData, not Keychain).
- **ExchangeProvider** — ignores `context.addresses`. Uses `context.accountId` to look up Keychain secrets (`"portu.exchange.<accountId>.apiKey"`) and `context.exchangeType` to route to the correct exchange client (Kraken, Binance, Coinbase).

### PriceService

Existing `PriceService` actor is retained with updates:
- CoinGecko public API for current prices (no key required)
- Historical price data for Asset Detail charts
- Rate limiter: max 10 requests/minute
- In-memory cache with 30s TTL
- Publishes via `AsyncThrowingStream<[String: Decimal], any Error>`

### Secrets

`KeychainService` stores all API credentials:
- Provider API keys: `"portu.provider.<dataSourceRawValue>.apiKey"` (e.g., `"portu.provider.debank.apiKey"`)
- Exchange credentials: `"portu.exchange.<accountId>.apiKey"`, `.apiSecret`, `.passphrase`
- RPC endpoints: stored in SwiftData (not secret), not Keychain

## Navigation

### Sidebar

```
┌─────────────────────┐
│  PORTU               │
├─────────────────────┤
│  ◉ Overview          │  ← default selection
│  ◉ Exposure          │
│  ◉ Performance       │
│                      │
│  PORTFOLIO           │
│  ◉ All Assets        │
│  ◉ All Positions     │
│                      │
│  MANAGEMENT          │
│  ◉ Accounts          │
│                      │
│  ─────────────────   │
│  (Strategies)        │  ← placeholder, future work
│                      │
│  ⚙ Settings (Cmd+,) │  ← separate window
└─────────────────────┘
```

### SidebarSection Enum

```swift
enum SidebarSection: Hashable, Sendable {
    case overview
    case exposure
    case performance
    case allAssets
    case allPositions
    case accounts
    // case strategies  // future work
}
```

### Navigation Pattern

- `NavigationSplitView` with sidebar + detail
- Sidebar uses `.listStyle(.sidebar)` with `Section` headers
- Detail column switches view based on `SidebarSection` selection
- Asset Detail is pushed within the detail column via `navigationDestination(for: Asset.ID.self)`
- Settings uses standard macOS `Settings { }` scene (Cmd+comma)

## Views

### 1. Overview View

The main dashboard. Default selection on app launch.

**Layout**: Two-column — main content (left, flex: 3) + inspector panel (right, flex: 1, collapsible).

**Top bar**: Total portfolio value, 24h absolute and percentage change, last synced timestamp, Sync button.

**Main content**:
- **Portfolio value chart** — Swift Charts `AreaMark`, time range selector (1w/1m/3m/1y/YTD). Data from PortfolioSnapshot.
- **Idle / Deployed / Futures cards** — three summary cards. Idle = positions with type `.idle` grouped by category (Stablecoins & Fiat, Majors, Tokens & Memecoins). Deployed = `.lending` + `.staking` + `.farming` + `.liquidityPool` grouped by sub-type (Lending, Staked, Yield). Futures = future work.
- **Tabbed positions list** — tabs: Key Changes, Idle Stables, Idle Majors, Borrowing. SwiftUI `Table` with sortable columns (Asset, Network/Account, Amount, Price, Value). Borrowing tab shows lending protocol positions with health factors.

**Inspector panel (right)**:
- **Top Assets** — donut chart via Swift Charts `SectorMark`. Toggle: By Category / By Asset. "See all →" navigates to All Assets.
- **Prices watchlist** — live price list for top portfolio assets. Configurable watchlist.

### 2. All Assets View

Tabbed view with 4 sub-tabs.

**Assets tab**: SwiftUI `Table` with sortable columns (Symbol, Name, Category, Net Amount, Price, Value). Search bar. Grouping options (Category, Price Source, Account Group). CSV export. Click row → pushes Asset Detail.

**NFTs tab**: Deferred to future work. Tab is visible but shows a placeholder ("NFT tracking coming soon"). NFT data model and provider integration will be defined in a separate spec.

**Platforms tab**: Table grouped by protocol. Columns: Platform, Share %, # Networks, # Positions, USD Balance. Derived from Position.protocolId grouping.

**Networks tab**: Table grouped by chain. Columns: Network, Share %, # Positions, USD Balance. Derived from Position.chain grouping.

### 3. All Positions View

Positions grouped by type and protocol, with a filter sidebar.

**Main content**: Nested sections. Top level grouped by position type (Idle Onchain, Idle Exchanges) and by protocol (Aave V3, Euler, LIDO, etc.). Each protocol section shows chain, health factor (if lending), and individual position tokens with supply/borrow roles.

**Filter sidebar (right)**: Position type filter (All, Idle, Lending, Liquidity Pool, Other) with USD totals. Protocol filter with selectable list. Uses SwiftData `@Query` predicates for filtering.

**"Add position" button**: For manual position entry.

### 4. Performance View

Time-series portfolio performance analysis.

**Controls**: Account filter dropdown, time range selector (1w/1m/3m/1y/YTD/Custom), chart mode toggle (Value/Assets/PnL).

**Chart modes**:
- **Value** — `AreaMark` showing total portfolio value over time. Data from PortfolioSnapshot (or AccountSnapshot when account-filtered).
- **Assets** — Stacked `AreaMark` broken down by asset category. Data from AssetSnapshot grouped by `category`, summing `usdValue` per timestamp. When account-filtered, AssetSnapshots are filtered by `accountId` first. Category filter chips toggle categories on/off.
- **PnL** — `BarMark` showing daily profit/loss. Cumulative toggle adds a `LineMark` overlay.

**Bottom panels**:
- **Asset categories** — category breakdown with period % change. Computed from AssetSnapshot: compare sum of `usdValue` per category at period start vs end.
- **Asset Prices** — table of top assets with start price, end price, and % change for selected period.

**Data**: Three snapshot tiers power this view:
- PortfolioSnapshot → Value mode (all accounts)
- AccountSnapshot → Value mode (account-filtered)
- AssetSnapshot → Assets mode (category breakdown, works with or without account filter)

**PnL computation**: Daily PnL = `snapshot[day N].totalValue - snapshot[day N-1].totalValue`. This is a simple mark-to-market PnL — deposits and withdrawals show as gains/losses. True cost-basis PnL is deferred to future work. If no snapshot exists for a given day (user didn't sync), that day is interpolated or skipped in the chart.

**Snapshot pruning**: Snapshots older than 7 days are pruned to one-per-day (keep the last snapshot of each day). Snapshots older than 90 days are pruned to one-per-week (keep the last snapshot of each week). Pruning runs after each sync. This keeps storage bounded while preserving enough granularity for charts.

### 5. Exposure View

Pure computed view — no extra persistence needed.

**Summary cards**: Spot total, Derivatives (Long/Short — future work), Net Exposure (excl. stablecoins).

**Exposure by asset category**: Table with columns: Category, Spot Assets/Liabilities, Spot Net, Derivatives Long/Short, Net Exposure. Uses `AssetCategory` enum values for grouping (Major, Stablecoin, DeFi, Meme, Privacy, Governance, Other). Individual assets within each category are visible in the "by asset" toggle below.

**Exposure by asset**: Table of individual assets with same columns. Toggle between Category view and flat asset list.

**Computation**:
- Spot = sum of all PositionToken values grouped by asset category
- Liabilities = PositionTokens with role `.borrow` (negative exposure)
- Net Exposure = Spot - Liabilities - Stablecoins
- Derivatives = future work (exchange futures positions)

### 6. Accounts View

Account management with CRUD operations.

**Account list**: SwiftUI `Table` with columns: Name, Group, Address (shows first address or exchange name), Type, USD Balance. Search, group filter (free-form String — groups are implicitly created by setting `Account.group`), status filter (Active/Inactive — toggled via context menu on rows). Sortable columns.

**Add Account sheet** (`.sheet` modal with `TabView`):
- **Chain account tab** — select chain ecosystem (Ethereum & L2s, Solana, Bitcoin — matching `Chain` enum families), paste address, set name/description/group. Select data source (DeBank/Zapper/RPC). For EVM addresses, a single WalletAddress with `chain: nil` is created, and the provider queries all EVM chains. For non-EVM (Solana, Bitcoin), `chain` is set explicitly. Toggle active/inactive status via context menu on account rows.
- **Manual account tab** — name + description only, for tracking non-supported assets.
- **Exchange account tab** — select exchange (Binance, Kraken, Coinbase, etc.), enter API key + secret (read-only permissions). Keys stored in Keychain.

**Bulk import**: Deferred to future work. Button visible but disabled with tooltip "Coming soon".

### 7. Asset Detail View

Drill-down view for a single asset. Pushed via `navigationDestination` from anywhere an asset is tapped.

**Breadcrumb**: ← Assets > ETH (back navigation).

**Price chart**: Swift Charts `LineMark`. Time range selector. Comparison toggles for BTC/SOL (normalized overlay lines). Three modes:
- **Price** — market price from CoinGecko historical API
- **$ Value** — total holdings value over time from AssetSnapshot (`usdValue` summed across all accounts for this `assetId`)
- **Amount** — token quantity over time from AssetSnapshot (`amount` summed across all accounts for this `assetId`)

**Holdings summary**: All Accounts count, total amount, total USD value. "On networks" section: table grouped by chain with amount, share %, USD value.

**Positions table**: All positions containing this asset. Columns: Account, Platform, Context (Staked/Idle/Lending), Network, Amount, USD Balance. Filterable by Context and Network.

**Right sidebar**: Asset metadata — Name, Symbol, Category. Link to external report/explorer.

## State Management

```swift
@Observable
class AppState {
    var selectedSection: SidebarSection = .overview
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]         // coinGeckoId → USD price
    var priceChanges24h: [String: Decimal] = [:] // coinGeckoId → 24h % change
    var connectionStatus: ConnectionStatus = .idle
    var syncStatus: SyncStatus = .idle
}

enum ConnectionStatus: Hashable, Sendable {
    case idle, fetching, error(String)
}

enum SyncStatus: Hashable, Sendable {
    case idle, syncing(progress: Double), error(String)
}
```

`AppState` holds only transient UI state. SwiftData `@Query` is used in views for all persistent data.

## Design Tokens

- **Theme**: Dark default. Semantic colors with dark-mode-first values. Light mode deferred.
- **Typography**: SF Pro via semantic styles (`.headline`, `.body`, `.caption`)
- **Icons**: SF Symbols exclusively
- **Colors**: Gold/amber accent (`#e8a838`), semantic gain/loss (green/red) with directional icons for accessibility
- **Number formatting**: `Text(value, format: .currency(code: "USD"))` and `.percent`
- **Charts**: Swift Charts exclusively — `AreaMark`, `BarMark`, `LineMark`, `SectorMark`
- **Tables**: SwiftUI `Table` with native sorting and column resizing
- **Animations**: `.spring` for state transitions, respect `accessibilityReduceMotion`

## Accessibility

- Toolbar buttons always include text labels
- Dynamic Type via semantic font styles only
- Reduce Motion: replace spring animations with opacity transitions
- P&L indicators: directional icons (↑/↓) alongside color, not color-only
- Financial data VoiceOver: clear `accessibilityLabel` values
- Menus: always include text with icons

## Implementation Phases

### Phase 1: Data Layer & API Foundation
Rework SwiftData models, implement `PortfolioDataProvider` protocol, build ZapperProvider (first concrete implementation — Zapper offers free API credits, DeBank requires a paid account), PriceService updates, SyncEngine, KeychainService updates.

### Phase 2: Sidebar & Overview View
Updated sidebar with all sections, Overview view as the reference implementation that validates the data model end-to-end.

### Phase 3: Fan-out to remaining views (independent, any order)
- All Assets View (4 sub-tabs)
- All Positions View (grouped list + filter sidebar)
- Performance View (3 chart modes + snapshots)
- Exposure View (computed aggregations)
- Accounts View (CRUD + Add Account sheet)
- Asset Detail View (drill-down with charts)

Each phase gets its own implementation plan document.

## Future Work (not in this spec)

- Auto-sync with configurable intervals
- Strategies view
- Light mode appearance
- DeBankProvider, RPCProvider implementations (after ZapperProvider proves the abstraction)
- Additional exchange integrations beyond Binance/Coinbase/Kraken
- NFT data model, provider integration, and display
- Transaction history
- Bulk import for accounts
- Derivatives / futures exposure tracking
- Sparkle auto-updates
- Notarization / distribution pipeline
- Multi-portfolio support
