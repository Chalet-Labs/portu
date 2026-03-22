# Portu — Full App Design Spec

## Overview

Portu is a native macOS SwiftUI crypto portfolio dashboard. It aggregates holdings from multiple data sources — Zapper API, exchange APIs, and manual entry — into a unified local-first interface. No backend server, no telemetry, no accounts. The provider abstraction supports future data sources (DeBank, direct RPC) without model changes.

This spec defines the complete application: data model, API layer, sync engine, navigation, and all 7 views. It supersedes the original scaffolding spec (`2026-03-14-portu-swiftui-app-design.md`).

## Requirements

- **Platform**: macOS 15.0+ (Sequoia)
- **Language**: Swift 6.2+
- **UI Framework**: SwiftUI with Swift Charts for all charting
- **Persistence**: SwiftData (local), Keychain (secrets)
- **Concurrency**: Default Main Actor isolation via `defaultIsolation(MainActor.self)` for **app target and PortuUI only**. PortuCore and PortuNetwork have **no default isolation**. PortuCore's `@Model` types must be accessed on MainActor (enforced by `ModelContext` being `@MainActor`); if the `@Model` macro does not apply `@MainActor` automatically, add explicit `@MainActor` annotations to each model class during implementation. DTOs, enums, and KeychainService must be freely usable from any isolation domain (`nonisolated` / plain `Sendable`). PortuNetwork's providers are `actor` types that run off the main thread
- **Build System**: XcodeGen (`project.yml`) + xcodebuild
- **Privacy**: All data local. No cloud. No telemetry.
- **Appearance**: Dark theme default, light mode support deferred to future work

## Architecture

### System Architecture

```
External Sources → PortuNetwork → PortuCore → App Views
```

**External Sources** (network boundary):
- Zapper API — DeFi positions, token balances (v1)
- Exchange APIs — Kraken, Binance, Coinbase balances (v1)
- CoinGecko — price feeds, market data, historical prices (v1)
- _DeBank API, RPC Nodes — deferred to future work_

**PortuNetwork** package:
- `PortfolioDataProvider` protocol — source-agnostic abstraction, returns **plain Sendable DTOs** (not SwiftData models)
- `ZapperProvider`, `ExchangeProvider` — v1 concrete implementations (_DeBankProvider, RPCProvider deferred_)
- `PriceService` — CoinGecko price cache + polling
- No SwiftData dependency — this package knows nothing about persistence

**PortuCore** package:
- SwiftData `@Model` types (Account, Position, PositionToken, Asset, etc.)
- Sync DTOs (`PositionDTO`, `TokenDTO`) — plain `Sendable` structs used as the transport format between PortuNetwork and the persistence layer. Asset metadata is carried inline on `TokenDTO` — there is no separate `AssetDTO`
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

**Manual-only portfolios**: If all accounts are manual (`dataSource == .manual`), Phase A
has zero accounts to process. Phase B still runs and creates snapshots from current manual
positions — manual entries deserve historical tracking just like synced data.

**Account.isActive semantics**: Inactive accounts are soft-hidden, not deleted. Their
positions persist in the database (user can reactivate), but are excluded from:
- Phase A sync loop (no fetch attempted)
- Phase B snapshots (positions from inactive accounts are not included in any snapshot tier)
- All view queries (views filter by `account.isActive == true` in `@Query` predicates or computed aggregations)
- Portfolio total, 24h change, Exposure, Net Amount — all exclude inactive account positions

**Phase A — Per-account fetch and persist** (loop over each active Account where `dataSource != .manual`):
1. Construct `SyncContext` from Account @Model
2. Resolve `PortfolioDataProvider` based on `dataSource`
3. Call `fetchBalances(context:)` → `[PositionDTO]`
4. Call `fetchDeFiPositions(context:)` → `[PositionDTO]` (empty if unsupported)
5. **Map DTOs → SwiftData** on the `ModelContext`:
   a. Upsert `Asset` @Model records using **Asset Identity upsert key hierarchy**
   b. Delete stale `Position` records from previous sync for this account
   c. Create new `Position` and `PositionToken` @Model instances
   d. Link PositionTokens to resolved Asset records
   e. `context.save()`
6. Update `Account.lastSyncedAt`, clear `Account.lastSyncError`
— end of per-account loop —

**Phase B — Snapshot all tiers from finalized state** (runs once, after all accounts complete):

All snapshots are created from the finalized position state in the database, not
during the per-account loop. This guarantees:
- All snapshot tiers share one timestamp and reflect the same point-in-time state
- Failed accounts' preserved positions are included in all tiers (Value and Assets modes agree)
- No timestamp drift between accounts

7. If ALL sync-attempted accounts failed AND no active manual accounts exist, skip Phase B entirely (no snapshot — nothing changed). Set `AppState.syncStatus = .error("All accounts failed to sync")` and return. If manual accounts exist, Phase B still runs — manual positions deserve historical tracking even when all remote syncs fail.
8. Generate `syncBatchId = UUID()` and `batchTimestamp = Date.now`
9. Query all current positions from the `ModelContext` **where `account.isActive == true`**
10. Create one `PortfolioSnapshot` (aggregate totals, `isPartial: true` if any sync-attempted account failed) — set `syncBatchId` and `timestamp = batchTimestamp`
11. Create one `AccountSnapshot` per active account (totals from each account's positions) — set `syncBatchId` and `timestamp = batchTimestamp`
12. Create `AssetSnapshot` records (one per asset per account, from current PositionTokens grouped by Asset and Account) — set `syncBatchId` and `timestamp = batchTimestamp`
13. Prune old snapshots (all three tiers)
14. `context.save()`
15. Update `AppState.syncStatus`: if any sync-attempted accounts failed → `.completedWithErrors(failedAccounts: [String])`, if all succeeded → `.idle`

**Error handling**: SyncEngine syncs accounts independently. If one account's provider fails:
- The error is recorded on that account (`Account.lastSyncError: String?`)
- Existing positions for that account are preserved (not deleted)
- Sync continues with remaining accounts
- `SyncStatus.completedWithErrors` persists until next sync or user dismisses — shows which accounts failed
- User can retry individual accounts or all failed accounts

**Partial-failure snapshots**: Phase B still creates snapshots when some accounts fail,
but marks them with `isPartial: true`. This is transparent about data quality:
- Failed accounts contribute stale positions (from their last successful sync) to the snapshot
- Value chart shows partial snapshots with a visual indicator (e.g., dashed line segment or muted dot)
- PnL computation treats partial→partial transitions normally, but partial→clean or clean→partial transitions show a warning tooltip ("some account data was stale, PnL may be inaccurate")
- If ALL accounts fail, no snapshot is written (nothing changed)

## Data Model

### Source-Agnostic Design

The data model is not coupled to any specific provider. All protocol-specific fields are optional. The `PortfolioDataProvider` protocol abstracts data sources — v1 ships with Zapper and Exchange clients, with the abstraction designed to support future providers (DeBank, RPC) without model changes. Features degrade gracefully when a less-rich provider is used:

| Feature | Zapper (v1) | Exchange (v1) | _DeBank (future)_ | _RPC (future)_ |
|---|---|---|---|---|
| Token balances | ✓ | ✓ | _✓_ | _✓_ |
| DeFi positions | ✓ | — | _✓_ | _—_ |
| Health factors | partial | — | _✓_ | _—_ |
| Protocol grouping | ✓ | — | _✓_ | _—_ |

UI hides unsupported features rather than showing broken/empty data. Each provider declares its capabilities via `ProviderCapabilities`.

### SwiftData Models

```
Account
├── id: UUID
├── name: String
├── kind: AccountKind              (.wallet, .exchange, .manual)
├── exchangeType: ExchangeType?    (set when kind == .exchange)
├── dataSource: DataSource         (.zapper, .exchange, .manual)
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
the provider (Zapper) fetches across all supported EVM chains automatically.
When chain is set (e.g., .solana), it restricts to that chain. Users create ONE
WalletAddress per 0x address, not one per chain.

Position                            — the core entity
├── id: UUID
├── positionType: PositionType     (.idle, .lending, .liquidityPool, .staking, .farming, .vesting, .other)
├── chain: Chain?                  (nil = off-chain: exchange custody, manual entry, etc.)
├── protocolId: String?            (Zapper protocol identifier; future: DeBank)
├── protocolName: String?
├── protocolLogoURL: String?
├── healthFactor: Double?          (lending positions only)
├── netUSDValue: Decimal           (pre-computed signed total: sum of token values with borrow subtracted)
├── tokens: [PositionToken]        (1:N, cascade delete)
├── account: Account?              (back-reference, nullify)
├── syncedAt: Date

PositionToken                       — bridges Position ↔ Asset
├── id: UUID
├── role: TokenRole                (.supply, .borrow, .reward, .stake, .lpToken, .balance)
├── amount: Decimal                (ALWAYS POSITIVE — role provides the sign, see Sign Convention below)
├── usdValue: Decimal              (ALWAYS POSITIVE — role provides the sign, see Sign Convention below)
├── asset: Asset?                  (N:1, nullify — assets are shared reference data)
├── position: Position?            (back-reference, nullify)

Asset                               — shared reference data, never cascade-deleted
├── id: UUID
├── symbol: String                 (e.g., "ETH", "WBTC")
├── name: String                   (e.g., "Ethereum")
├── coinGeckoId: String?           (tier 1 upsert key — cross-chain canonical identity)
├── upsertChain: Chain?            (tier 2 upsert key only — NOT the "home chain" of the asset)
├── upsertContract: String?        (tier 2 upsert key only — NOT a canonical contract address)
├── sourceKey: String?             (tier 3 upsert key — provider-specific opaque ID)
├── debankId: String?              (reserved for future DeBankProvider — unused in v1)
├── logoURL: String?
├── category: AssetCategory        (.major, .stablecoin, .defi, .meme, .privacy, .fiat, .governance, .other)
├── isVerified: Bool
Note: Asset is a LOGICAL entity, not a deployment. For cross-chain assets
(tier 1 match by coinGeckoId), upsertChain and upsertContract are nil.
Chain-specific provenance (which chain a token lives on, explorer links)
comes from Position.chain, not from Asset. The upsert fields exist solely
for deduplication of single-chain tokens that lack a coinGeckoId.

PortfolioSnapshot                   — append-only time series for Performance view
├── id: UUID
├── syncBatchId: UUID              (shared key across all snapshot tiers in one batch)
├── timestamp: Date
├── totalValue: Decimal
├── idleValue: Decimal
├── deployedValue: Decimal
├── debtValue: Decimal
├── isPartial: Bool                (true if any account failed during this sync batch)

AccountSnapshot                     — per-account time series for account-filtered Performance
├── id: UUID
├── syncBatchId: UUID              (joins to PortfolioSnapshot.syncBatchId)
├── timestamp: Date
├── accountId: UUID                (not a relationship — survives account deletion for historical data)
├── totalValue: Decimal
├── isFresh: Bool                  (true = synced successfully or manual account; false = remote sync failed, data is stale)

AssetSnapshot                       — per-asset per-account time series
├── id: UUID
├── syncBatchId: UUID              (joins to PortfolioSnapshot.syncBatchId)
├── timestamp: Date
├── accountId: UUID                (not a relationship — survives deletion)
├── assetId: UUID                  (not a relationship — survives deletion)
├── symbol: String                 (denormalized for display — survives Asset changes)
├── category: AssetCategory        (denormalized — enables category grouping without joins)
├── amount: Decimal                (GROSS POSITIVE: supply + balance + stake + lpToken)
├── usdValue: Decimal              (GROSS POSITIVE: supply + balance + stake + lpToken)
├── borrowAmount: Decimal          (ABSOLUTE POSITIVE: borrow role tokens only, 0 if none)
├── borrowUsdValue: Decimal        (ABSOLUTE POSITIVE: borrow role tokens only, 0 if none)
**Partial-batch detection** — all snapshot tiers share `syncBatchId` (UUID) as the
relational key. This is more robust than timestamp equality and survives precision
changes, imports, or pruning behavior changes.

Three levels of granularity:
- **Portfolio-wide**: `PortfolioSnapshot.isPartial` — was any account stale in this batch?
- **Per-account**: `AccountSnapshot.isFresh` — was this specific account successfully synced? Joined to PortfolioSnapshot via `syncBatchId`.
- **Per-asset**: AssetSnapshot inherits freshness from AccountSnapshot with matching `accountId + syncBatchId`

Views use the appropriate level:
- All-accounts Performance chart → check `PortfolioSnapshot.isPartial`
- Account-filtered Performance → check `AccountSnapshot.isFresh` for the selected account (no false alarms from other accounts' failures)
- Asset Detail → if viewing across all accounts, check `PortfolioSnapshot.isPartial`; if account context is known, check `AccountSnapshot.isFresh`

AssetSnapshot stores gross and borrow values separately (both always positive):
  supply/balance/stake/lpToken → summed into `amount` and `usdValue`
  borrow → summed into `borrowAmount` and `borrowUsdValue`
  reward → excluded from both
All assets get an AssetSnapshot row, including borrow-only assets (where amount=0, borrowAmount>0).

How each view uses these fields:
  Performance "Assets" mode → `usdValue` only (gross, positive → stacked AreaMark works)
  Asset Detail "$ Value" → `usdValue - borrowUsdValue` (net value over time)
  Asset Detail "Amount" → `amount - borrowAmount` (net amount over time)
  Asset Detail for borrow-only assets → shows debt history from borrowUsdValue
  Exposure view → computed LIVE from current PositionTokens (no snapshot dependency)
```

AssetSnapshot enables:
- **Performance "Assets" mode** — group by `category`, sum `usdValue`, chart over time as stacked AreaMark
- **Performance account filter + category breakdown** — filter by `accountId`, then group by `category`
- **Asset Detail "$ Value" mode** — filter by `assetId`, chart `usdValue - borrowUsdValue` (net) over time
- **Asset Detail "Amount" mode** — filter by `assetId`, chart `amount - borrowAmount` (net) over time
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

### Sign Convention

**Invariant: `PositionToken.amount` and `PositionToken.usdValue` are always positive (absolute values).
`TokenRole` provides the sign semantics. `Position.netUSDValue` is the pre-computed signed aggregate.**

This matches how providers return data (always positive) and keeps display simple.

**Role sign mapping:**

| Role | Sign in aggregations | Example |
|---|---|---|
| `.balance` | + | 10 ETH idle in wallet → amount: 10, usdValue: 21,880 |
| `.supply` | + | 3.68 WBTC supplied to Aave → amount: 3.68, usdValue: 262,429 |
| `.borrow` | − | 0.03 csBTC borrowed → amount: 0.03, usdValue: 2,193 |
| `.reward` | excluded | 0.5 AAVE unclaimed → amount: 0.5, usdValue: 50 |
| `.stake` | + | 15.16 stETH staked → amount: 15.16, usdValue: 35,762 |
| `.lpToken` | + | LP token position → amount: 100, usdValue: 5,000 |

**How each formula applies signs:**

- **Position.netUSDValue** = `sum(token.usdValue where role is +) − sum(token.usdValue where role is .borrow)`. **Computed exclusively by SyncEngine** when creating Position @Model from PositionDTO — not provided by the DTO. SyncEngine is the single owner of this derived value.
- **Net Amount** (All Assets) = `sum(token.amount where role is +) − sum(token.amount where role is .borrow)`, for tokens referencing the same Asset. `.reward` excluded.
- **Exposure** = same as Net Amount but grouped by category. Borrow subtracts from exposure.
- **24h change** = `sum(token.amount × livePrice × priceChange24hPct)` for `+` roles, minus the same for `.borrow` roles. Rewards excluded.
- **Portfolio total** = `sum(Position.netUSDValue)` across all positions. Already signed correctly.

**Value display by row type:**

| Row type | Amount shown | Value shown | Sign |
|---|---|---|---|
| **PositionToken row** (Overview tabs, All Positions sub-rows) | `token.amount` (always positive) | `token.amount × livePrice` or `token.usdValue` fallback | Always positive. Borrow rows show "Borrow" label, not minus sign. |
| **Aggregated asset row** (All Assets table) | Net Amount (borrow subtracted) | `netAmount × livePrice` — can be negative if borrow > supply | Signed. Negative values displayed as "−$X" |
| **Position group header** (All Positions protocol sections) | — | `position.netUSDValue` | Signed. Shows net total for the position. |

### Price Display Rules

Prices come from two sources. The rules for which to use:

1. **Live price** (`AppState.prices[asset.coinGeckoId]`) — used when `coinGeckoId` is present and PriceService has a cached value. This is the authoritative price for display.
2. **Sync-time fallback** — used when the asset has no `coinGeckoId`. Displayed with a "stale" indicator showing sync time. Rules differ by row type:
   - **PositionToken row**: Price = `token.usdValue / token.amount`. Value = `token.usdValue`.
   - **Aggregated asset row** (All Assets): Price = weighted average `sum(token.usdValue for + roles) / sum(token.amount for + roles)`. Value = `sum(token.usdValue for + roles) − sum(token.usdValue for .borrow roles)` (direct sum of sync-time values, not price × netAmount).

For "24h change" in the Overview top bar: see **Sign Convention** section for the canonical formula (role-sign-adjusted). Assets without `coinGeckoId` contribute $0 (shown as approximate with a tooltip).

### Asset Identity and Upsert Rules

Assets are shared reference data. Multiple PositionTokens across accounts and providers
can reference the same Asset. The upsert rules define how SyncEngine deduplicates tokens
into canonical Asset records.

**Upsert key hierarchy** (checked in order, first match wins):

1. **`coinGeckoId`** — primary key when present. One Asset per coinGeckoId. This naturally
   handles cross-chain grouping: ETH on Ethereum, ETH on Arbitrum, and staked ETH variants
   all map to coinGeckoId `"ethereum"` (or their own IDs like `"lido-staked-ether"`).
   Most assets with real value have a coinGeckoId.

2. **`upsertChain + upsertContract`** — for on-chain tokens without a coinGeckoId. Unique per
   deployment. Two tokens on different chains are different Assets. These fields are only
   set on Assets matched via this tier; cross-chain assets (tier 1) leave them nil.

3. **`sourceKey`** — provider-specific opaque identifier. Each provider generates a stable,
   unique key for tokens that lack both coinGeckoId and upsertChain+upsertContract. Examples:
   - ZapperProvider: `"zapper:<zapper_token_id>"`
   - ExchangeProvider: `"kraken:KFEE"`, `"binance:BNB"` (exchange + symbol)
   - RPCProvider: never hits tier 3 (always has upsertChain+upsertContract)
   Both `TokenDTO.sourceKey` and `Asset.sourceKey` carry this value. If no existing Asset
   matches any tier, a new Asset is created. This avoids false merges across providers
   while still deduplicating within a provider.

**Merge precedence** — when multiple providers return data for the same Asset:
- Prefer records with `coinGeckoId` set over those without
- Prefer `isVerified: true` over `false`
- For conflicting metadata (name, category, logoURL): last-synced-wins, since newer data
  from providers is generally more accurate
- `coinGeckoId`, `upsertChain`, `upsertContract`, and `sourceKey` are never overwritten once set (append-only on these fields)

**WBTC vs BTC**: These are separate Assets (different coinGeckoIds: `"wrapped-bitcoin"` vs
`"bitcoin"`). The `AssetCategory` grouping (both are `.major`) handles the logical "BTC
exposure" concept in Exposure and Overview views.

**Edge case — unknown tokens**: If a provider returns a token that matches no existing Asset
by any key, a new Asset is created with whatever data the provider supplied. If `coinGeckoId`
is absent, PriceService cannot provide live prices — the view falls back to sync-time
`PositionToken.usdValue`.

### Net Amount Aggregation

"Net Amount" in the All Assets table = sum of all PositionToken amounts for that Asset
(matched by Asset.id after upsert) across all accounts and positions. Tokens with role
`.borrow` subtract from the total. Tokens with role `.reward` are excluded (unclaimed
rewards). This gives net exposure per asset.

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
    case zapper, exchange, manual
    // case debank  — deferred (paid API)
    // case rpc     — deferred
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
    let chain: Chain?              // nil for exchange/manual (off-chain)
    let protocolId: String?
    let protocolName: String?
    let protocolLogoURL: String?
    let healthFactor: Double?
    // netUSDValue is NOT here — SyncEngine computes Position.netUSDValue
    // from token roles using the sign convention (see Sign Convention section)
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
    let sourceKey: String?         // provider-specific opaque ID (e.g., "kraken:KFEE")
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
1. Upserts `Asset` records from `TokenDTO` fields using the Asset Identity upsert key hierarchy (coinGeckoId → upsertChain+upsertContract → sourceKey). `TokenDTO.chain` maps to `Asset.upsertChain`, `TokenDTO.contractAddress` maps to `Asset.upsertContract` — these are set only for tier 2 matches (nil for cross-chain tier 1 assets).
2. Creates `Position` @Model instances from `PositionDTO`
3. Creates `PositionToken` @Model instances from `TokenDTO`, linking to upserted Assets
4. All writes happen in a single `ModelContext.save()` call per account

### Provider Implementations

Each provider uses `SyncContext` differently:

- **ZapperProvider** — iterates `context.addresses`, calls Zapper API for each address across all chains (or specific chain if `address.chain` is set). Merges results. User provides API key (stored as `"portu.provider.zapper.apiKey"`). **← first implementation (free API credits)**
- **ExchangeProvider** — ignores `context.addresses`. Uses `context.accountId` to look up Keychain secrets (`"portu.exchange.<accountId>.apiKey"`) and `context.exchangeType` to route to the correct exchange client (Kraken, Binance, Coinbase).
- ~~**DeBankProvider**~~ — deferred. Same pattern as Zapper but uses DeBank Cloud API (requires paid account).
- ~~**RPCProvider**~~ — deferred. Iterates `context.addresses`, queries ERC-20 balances via `eth_call` per chain. Balances only.

### PriceService

Existing `PriceService` actor is retained with updates:
- CoinGecko public API for current prices AND 24h change percentages (both returned by `/simple/price?include_24hr_change=true`)
- Historical price data for Asset Detail charts
- Rate limiter: max 10 requests/minute
- In-memory cache with 30s TTL
- Publishes via `AsyncThrowingStream<PriceUpdate, any Error>` where:
  ```swift
  struct PriceUpdate: Sendable {
      let prices: [String: Decimal]          // coinGeckoId → USD price
      let changes24h: [String: Decimal]      // coinGeckoId → 24h % change
  }
  ```
- AppState subscribes to this stream and updates both `prices` and `priceChanges24h` atomically from each `PriceUpdate`

### Secrets

`KeychainService` stores all API credentials:
- Provider API keys: `"portu.provider.<dataSourceRawValue>.apiKey"` (e.g., `"portu.provider.zapper.apiKey"`)
- Exchange credentials: `"portu.exchange.<accountId>.apiKey"`, `.apiSecret`, `.passphrase`

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

**Top bar**: Total portfolio value, 24h absolute and percentage change, last synced timestamp (= `batchTimestamp` of most recent sync run, regardless of partial status; partial failures shown separately via `completedWithErrors` badge), Sync button.

**Main content**:
- **Portfolio value chart** — Swift Charts `AreaMark`, time range selector (1w/1m/3m/1y/YTD). Data from PortfolioSnapshot.
- **Idle / Deployed / Futures cards** — three summary cards. Idle = positions with type `.idle` grouped by category (Stablecoins & Fiat, Majors, Tokens & Memecoins). Deployed = `.lending` + `.staking` + `.farming` + `.liquidityPool` grouped by sub-type (Lending, Staked, Yield). Futures = future work.
- **Tabbed positions list** — tabs: Key Changes, Idle Stables, Idle Majors, Borrowing. All tabs display **PositionToken-level rows** (one row per token, not per position). Row contract per tab:
  - **Key Changes / Idle Stables / Idle Majors**: flat token rows. Columns: Asset (token symbol), Network/Account (Position.chain + Account.name), Amount (token.amount), Price (live or fallback), Value (amount × price). Uses PositionToken row display rules (always positive).
  - **Borrowing**: grouped by protocol. Section header shows protocol name, chain, health factor. Sub-rows are PositionToken rows with role prefix (→ Supply, ← Borrow). Borrow rows show positive values with "Borrow" label per the sign convention.

**Inspector panel (right)**:
- **Top Assets** — donut chart via Swift Charts `SectorMark`. Toggle: By Category / By Asset. "See all →" navigates to All Assets.
- **Prices watchlist** — live price list for top portfolio assets. Configurable watchlist.

### 2. All Assets View

Tabbed view with 4 sub-tabs.

**Assets tab**: SwiftUI `Table` with sortable columns (Symbol, Name, Category, Net Amount, Price, Value). Search bar. Grouping options (Category, Price Source, Account Group). CSV export. Click row → pushes Asset Detail.

**NFTs tab**: Deferred to future work. Tab is visible but shows a placeholder ("NFT tracking coming soon"). NFT data model and provider integration will be defined in a separate spec.

**Platforms tab**: Table grouped by protocol. Columns: Platform, Share %, # Networks, # Positions, USD Balance. Derived from Position.protocolId grouping.

**Networks tab**: Table grouped by chain. Columns: Network, Share %, # Positions, USD Balance. Derived from Position.chain grouping. Positions with `chain == nil` (exchange/manual) are grouped under an "Off-chain / Custodial" row.

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
- Spot Assets = sum of PositionToken.usdValue where role is positive (`.supply`, `.balance`, `.stake`, `.lpToken`), grouped by asset category. Borrow and reward tokens are NOT included in Spot.
- Liabilities = sum of PositionToken.usdValue where role is `.borrow`, grouped by asset category
- Spot Net = Spot Assets − Liabilities (per category)
- Net Exposure = Spot Net − Stablecoins (excludes stablecoin category from exposure total)
- Derivatives = future work (exchange futures positions)

### 6. Accounts View

Account management with CRUD operations.

**Account list**: SwiftUI `Table` with columns: Name, Group, Address (shows first address or exchange name), Type, USD Balance. Search, group filter (free-form String — groups are implicitly created by setting `Account.group`), status filter (Active/Inactive — toggled via context menu on rows). Sortable columns.

**Add Account sheet** (`.sheet` modal with `TabView`):
- **Chain account tab** — select chain ecosystem (Ethereum & L2s, Solana, Bitcoin — matching `Chain` enum families), paste address, set name/description/group. Data source is Zapper (v1 only provider for on-chain accounts). For EVM addresses, a single WalletAddress with `chain: nil` is created, and the provider queries all EVM chains. For non-EVM (Solana, Bitcoin), `chain` is set explicitly. Toggle active/inactive status via context menu on account rows.
- **Manual account tab** — name + description only, for tracking non-supported assets.
- **Exchange account tab** — select exchange (Binance, Kraken, Coinbase, etc.), enter API key + secret (read-only permissions). Keys stored in Keychain.

**Bulk import**: Deferred to future work. Button visible but disabled with tooltip "Coming soon".

### 7. Asset Detail View

Drill-down view for a single asset. Pushed via `navigationDestination` from anywhere an asset is tapped.

**Breadcrumb**: ← Assets > ETH (back navigation).

**Price chart**: Swift Charts `LineMark`. Time range selector. Comparison toggles for BTC/SOL (normalized overlay lines). Three modes:
- **Price** — market price from CoinGecko historical API
- **$ Value** — net holdings value over time from AssetSnapshot: `sum(usdValue) - sum(borrowUsdValue)` across all accounts for this `assetId`. For borrow-only assets this is negative, displayed as "Debt: $X".
- **Amount** — net token quantity over time from AssetSnapshot: `sum(amount) - sum(borrowAmount)` across all accounts for this `assetId`. For borrow-only assets this is negative, displayed as "Borrowed: X".

**Holdings summary**: All Accounts count, total amount, total USD value. "On networks" section: table grouped by `Position.chain` (not Asset.upsertChain) with amount, share %, USD value. This correctly shows all chains where the asset is held.

**Positions table**: All positions containing this asset. Columns: Account, Platform, Context (Staked/Idle/Lending), Network, Amount, USD Balance. Filterable by Context and Network.

**Right sidebar**: Asset metadata — Name, Symbol, Category. Explorer links are per-position (using Position.chain), not per-asset, since a cross-chain asset has no single canonical chain.

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
    case idle
    case syncing(progress: Double)
    case completedWithErrors(failedAccounts: [String])  // partial failure — persists until next sync or dismissed
    case error(String)                                   // total failure (all accounts failed or infra error)
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
Rework SwiftData models, implement `PortfolioDataProvider` protocol, build ZapperProvider and ExchangeProvider, PriceService updates, SyncEngine, KeychainService updates.

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
