# Zerion Portfolio Analytics Behavioral Spec

## Terminology

### B1: Value Change replaces the misleading PnL chart

- `PerformanceChartMode.pnl` becomes `.valueChange` with label
  `Value Change`.
- `PnLChartMode`, `PnLBar`, `computePnLBars`, and PnL-named snapshot-delta
  tests/helpers receive Value Change names.
- The calculation remains the difference between consecutive observed local
  snapshot values.
- The UI states that deposits, withdrawals, and transfers may affect Value
  Change.
- True FIFO P&L is a separate mode.

### B2: Incomplete local transitions are not silently authoritative

- Value Change uses transitions only when both adjacent observations represent
  the intended selected scope.
- A failed account snapshot (`isFresh == false`) does not establish a provider
  splice boundary.
- Any omitted or qualified transition behavior must be visible rather than
  silently presenting a precise gain/loss.

## Eligibility and scope

### B3: Eligible selected account

Analytics requests run only when all conditions hold:

- A concrete account is selected.
- `account.isActive == true`.
- `account.dataSource == .zerion`.
- At least one configured address is valid and supported.
- The local analytics feature gate is enabled.

All Accounts and `.zapper`, `.exchange`, `.manual`, inactive, invalid-address,
and unsupported scopes issue no Zerion analytics request.

### B4: Address normalization

- Trim surrounding whitespace.
- Validate address family before normalization.
- EVM identity is lowercase hexadecimal; EIP-55 casing is not used in cache
  keys.
- Valid Solana base58 identity preserves exact case.
- Deduplicate after normalization.
- Sort deterministically by family and canonical address.
- Reject invalid or ambiguous addresses.

### B5: Wallet routing

- One address uses a wallet endpoint.
- Exactly one EVM plus one Solana address may use the matching wallet-set
  endpoint after its live gate passes.
- Multiple addresses of the same family use separate wallet requests.
- Independent wallet P&L values are never summed.
- If wallet-set P&L is unavailable or incomplete, show separate wallet results
  with no combined total.

## Wallet balance history

### B6: Chart range mapping

- 1W uses `week`.
- 1M uses `month`.
- 3M uses `3months`.
- 1Y uses `year`.
- YTD uses `month` for elapsed year days 1–31, `3months` for days 32–90,
  otherwise `year`, then trims to the local calendar-year boundary.
- Custom is unavailable until a real custom-date picker exists.
- Requests use USD. EVM-only charts request `filter[positions]=no_filter`;
  scopes containing Solana omit that unsupported filter and retain an explicit
  provider-reported coverage label.

### B7: Chart normalization

- Decode second-based timestamps.
- Reject malformed, non-finite, or negative values.
- Reduce multiple points on one UTC day to the latest timestamp.
- Sort by UTC day then timestamp deterministically.
- Preserve provider coverage and fetch provenance.

### B8: Provider/local splice

- Find the earliest selected-account `AccountSnapshot` whose `isFresh` is true.
- Provider points are eligible only on UTC days strictly before that day.
- Local observations own the boundary day and every later day, including gaps
  after failed syncs.
- If no fresh local snapshot exists, provider history may cover the full
  requested range.
- If the earliest fresh local day predates every provider point, use local
  history only.
- Provider history never enters the All Accounts chart.
- Provider history replaces fixed-holdings estimation only for the covered
  selected Zerion account period.
- Fixed-holdings estimation remains fallback when provider history is absent.

### B9: Historical display currency

- Cache wallet chart values in USD.
- USD display requires no FX cache.
- EUR/CHF requests historical FX from the earliest retained chart day through
  today, capped to 400 days.
- Convert each point with its matching historical day.
- Never substitute today's spot rate for a missing historical day.
- On missing FX, show the longest contiguous converted suffix and disclose the
  earliest available conversion date.

### B10: Chart cache retention

- Logical identity is account + scope fingerprint + provider + coverage + UTC
  day.
- Latest timestamp wins for duplicate logical days.
- A successful write retains at most 400 UTC days per logical scope.
- Scope edits remove obsolete-scope rows without touching other accounts.
- Refresh failure never deletes the last successful cache.

## FIFO P&L

### B11: Supported P&L ranges

- All time sends no `since`.
- 1D, 1W, 1M, 1Y, and YTD send the documented millisecond `since` boundary.
- P&L has its own range state and control.
- 3M and Custom are neither silently coerced nor shown as unexplained disabled
  options.
- Returning to chart modes restores the parent chart range.

### B12: Direct display currency

- P&L is requested directly in USD, EUR, or CHF according to Portu display
  currency.
- Aggregate P&L is never converted using one current FX rate.

### B13: P&L normalization

Normalize:

- Total, realized, and unrealized gain and percentages.
- Fees, total invested, realized cost basis, and net invested.
- Received/sent external value and NFT flows.
- FIFO method, range, currency, provider, and fetch time.
- Per-implementation average prices and gain/cost/flow metrics.
- Excluded fungible IDs and implementations as partial-success metadata.

Decoder correctness must not depend on one documented resource-type string.
Unresolvable implementation IDs remain opaque display/exclusion identifiers and
do not become canonical Portu asset identities.

### B14: Filtered breakdown

- Filter currently held canonical implementations in deterministic batches of
  at most 100 and within a safe request URL length.
- Filtered responses provide independently attributable rows.
- Filtered batch totals are never summed into an overall P&L.
- Excluded identifiers remain visible.

### B15: P&L cache freshness

Using `fetchedAt` and an injected clock:

- Younger than 24 hours is fresh and does not auto-refresh on entry.
- From 24 hours through less than 30 days is stale, renders immediately with
  age/provider attribution, and refreshes at most once per feature entry.
- At least 30 days old remains visible but refreshes and is expected to
  potentially enter Zerion bootstrap.
- Failure or cancellation never advances `fetchedAt` or replaces the last
  success.
- Cache identity includes account, scope fingerprint, range, and currency.

## Reducer behavior

### B16: Parent/child ownership

- `PerformanceFeature.State` owns selected account, chart range, and chart mode.
- `PortfolioAnalyticsFeature.State` owns P&L range, request fingerprint,
  request status, normalized result, cache age, and typed error.
- The child derives parent selection changes through reducer composition; it
  does not mirror parent account/chart state.

### B17: Cache-first refresh

- Load matching cache first and render it immediately.
- Refresh on first eligible entry only when cache is absent or stale.
- Explicit refresh always starts a new eligible request.
- A new account/range/currency request cancels the previous request.
- Every response carries a request fingerprint; obsolete responses cannot
  overwrite current state if cancellation races.

### B18: Typed outcomes

- `preparing`: `503`; honor `Retry-After` with bounded polling and a two-minute
  absolute cap.
- `planUnavailable`: `402`; explain plan setup.
- `invalidCredential`: `401` or `403`; direct to Zerion API key settings.
- `invalidRequest`: `400`; do not retry.
- `unavailableForScope`: `404`; preserve cache and do not turn it into zero.
- `rateLimited`: `429`; preserve cache and do not run an uncontrolled retry.
- `unsupportedAggregation`: render separate wallet sections with no total.
- Missing/excluded assets are partial success.
- Cancellation is not surfaced as failure.

### B19: Inactive account transition

- If the selected account becomes inactive during the session, preserve its
  cached read-only result, display an inactive state, and disable refresh.
- Inactive accounts remain absent from normal account selection.

## UI and disclosure

### B20: Performance mode controls

- Mode order is Value, Assets, Value Change, PnL.
- Chart modes use the parent chart-range control.
- PnL mode replaces it with a clearly labeled P&L-specific control.

### B21: P&L presentation

Show:

- Total, realized, and unrealized P&L.
- Net invested and fees.
- External and NFT flow disclosure.
- Per-asset breakdown when present.
- Excluded/unpriced identifiers.
- Zerion attribution, FIFO, selected range, direct currency, fetched time, and
  freshness.
- Text/icons in addition to color for gain and loss.

State that unrealized gain uses current prices even for a historical `since`
range and that results are estimates, coverage may be incomplete, and they are
not tax advice.

### B22: Percentage rounding

If displayed component percentages must sum to 100%, round each display value
first and apply the residual to the largest stable row.

## Persistence lifecycle

### B23: Clear and invalidate

- Address/chain/provider edits invalidate the obsolete analytics scope.
- Account deletion removes that account's provider analytics.
- Deactivation preserves cache but suppresses refresh.
- Clear Analytics removes only the selected account's provider chart/P&L cache.
- It does not delete holdings, local snapshots, asset price history, FX history,
  or another account's analytics.

## Diagnostics and rollout

### B24: Portfolio reconciliation

- `/portfolio` is opt-in debug/live-test diagnostics only.
- Compare Zerion position total with Portu's decoded net position total using
  explicit absolute and relative tolerance.
- Do not call it in scheduled sync or routinely persist its raw response.

### B25: Feature gate

- Value Change terminology is always available.
- Zerion analytics default off until terms, entitlement, fixtures, and live
  contract gates pass.
- Availability enters TCA through a dependency/state boundary; views do not
  read `@AppStorage` directly.

### B26: Privacy and live tests

- Store normalized values only.
- Do not store raw response bodies, authentication, or transaction corpora.
- Do not log secrets or full wallet addresses.
- Sanitized fixtures contain no private user address or identifying portfolio.
- Live tests require both `PORTU_ZERION_LIVE_TESTS=1` and `ZERION_API_KEY`.
