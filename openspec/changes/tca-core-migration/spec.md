# AppFeature Behavioral Spec

## State

| Property | Type | Default | Description |
|---|---|---|---|
| selectedSection | SidebarSection | .overview | Current navigation section |
| syncStatus | SyncStatus | .idle | Sync orchestration state |
| connectionStatus | ConnectionStatus | .idle | Network/price fetch state |
| prices | [String: Decimal] | [:] | CoinGecko ID → USD price |
| priceChanges24h | [String: Decimal] | [:] | CoinGecko ID → 24h change % |
| lastPriceUpdate | Date? | nil | Timestamp of last price fetch |
| storeIsEphemeral | Bool | false | True if SwiftData fell back to in-memory |

## Actions

### User Actions
- `sectionSelected(SidebarSection)` — User taps sidebar item
- `syncTapped` — User triggers manual sync
- `startPricePolling([String])` — Begin periodic price updates for given coin IDs
- `stopPricePolling` — Stop price polling

### Internal Actions
- `syncCompleted(Result<SyncResult, Error>)` — Sync finished
- `syncProgressUpdated(Double)` — Sync progress changed
- `pricesReceived(PriceUpdate)` — New prices from polling
- `priceFetchFailed(Error)` — Price fetch error

## Behaviors

### B1: Section Navigation
- WHEN `sectionSelected` is sent
- THEN `state.selectedSection` updates to the new section
- AND no side effects run

### B2: Sync — Happy Path
- WHEN `syncTapped` is sent AND syncStatus is `.idle`
- THEN `state.syncStatus` becomes `.syncing(progress: 0)`
- AND sync effect starts (calls SyncEngineClient.sync)
- WHEN `syncProgressUpdated(progress)` is received
- THEN `state.syncStatus` becomes `.syncing(progress: progress)`
- WHEN `syncCompleted(.success(result))` is received
- THEN `state.syncStatus` becomes `.idle`

### B3: Sync — Partial Failure
- WHEN `syncCompleted(.success(result))` is received AND result has failed accounts
- THEN `state.syncStatus` becomes `.completedWithErrors(failedAccounts: [names])`

### B4: Sync — Full Failure
- WHEN `syncCompleted(.failure(error))` is received
- THEN `state.syncStatus` becomes `.error(error.localizedDescription)`

### B5: Sync — Guard Against Double-Tap
- WHEN `syncTapped` is sent AND syncStatus is NOT `.idle`
- THEN no state change, no effect

### B6: Price Polling — Start
- WHEN `startPricePolling(coinIds)` is sent
- THEN a long-running price polling effect starts
- AND `state.connectionStatus` becomes `.fetching`

### B7: Price Polling — Receive
- WHEN `pricesReceived(update)` arrives
- THEN `state.prices` merges with update.prices
- AND `state.priceChanges24h` merges with update.changes
- AND `state.lastPriceUpdate` updates to now
- AND `state.connectionStatus` becomes `.idle`

### B8: Price Polling — Error
- WHEN `priceFetchFailed(error)` arrives
- THEN `state.connectionStatus` becomes `.error(error.localizedDescription)`
- AND existing prices are NOT cleared (stale-while-revalidate)

## Constraints

- SyncEngine logic stays in SyncEngine — the reducer delegates via dependency, not reimplements
- SwiftData ModelContext is NOT a TCA dependency — views keep @Query
- Price polling must be cancellable (cancel previous when new coinIds arrive)
- All state mutations must go through the reducer — no direct AppState mutation
