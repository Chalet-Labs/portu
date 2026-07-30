# Zerion Portfolio Analytics

## What

Add Zerion-sourced wallet balance history and FIFO profit-and-loss analytics for
eligible Zerion accounts. Correct the existing snapshot-delta chart terminology
from `PnL` to `Value Change`.

The analytics feature is local-only, BYOK, on demand, and default-off until the
configured Zerion plan is authenticated against every required endpoint.

## Why

Portu currently stores observed portfolio snapshots and estimates earlier value
history from fixed holdings and historical prices. Its existing `PnL` chart is
not cost-basis P&L: it subtracts consecutive snapshot values and therefore
includes deposits and withdrawals.

Zerion exposes wallet balance charts and FIFO P&L with realized gain,
unrealized gain, fees, invested amounts, external flows, and per-implementation
breakdowns. Those values are useful for supported onchain accounts, but they do
not describe exchange, manual, or mixed-provider portfolios.

## Scope

### In scope

- Rename the existing snapshot-delta mode and related types to `Value Change`.
- Fetch and cache normalized Zerion wallet and supported wallet-set charts.
- Splice provider history strictly before Portu's first successful local
  account-snapshot day.
- Fetch and cache the latest Zerion FIFO P&L for an eligible selected account.
- Show overall and per-asset P&L, fees, flows, exclusions, provenance,
  freshness, and coverage limitations.
- Preserve cached analytics across offline, quota, entitlement, and bootstrap
  failures.
- Provide account-scoped cache deletion and deterministic invalidation.
- Add opt-in portfolio reconciliation diagnostics.

### Out of scope

- Global P&L across exchanges, manual accounts, and Zerion accounts.
- Summing independent wallet P&L results.
- Transfer linking or a provider-neutral cash-flow ledger.
- Historical realized/unrealized P&L time series.
- Tax-lot methods other than Zerion FIFO.
- Transaction feeds, NFTs, webhooks, swaps, gas, or scheduled P&L polling.
- Custom P&L dates until Portu has a real custom-date picker.

## Architecture

- `PortuCore` owns Sendable normalized values and SwiftData cache models.
- `PortuNetwork` owns a Zerion-specific analytics capability implemented by the
  existing actor-based `ZerionProvider`.
- The app target owns cache orchestration through a small
  `PortfolioAnalyticsClient` TCA dependency.
- `PortfolioAnalyticsFeature` is a child of `PerformanceFeature`.
- `PerformanceFeature.State` remains authoritative for selected account and
  chart range. The child owns only analytics-specific state, including the P&L
  range, request status, cached result, and typed error.
- Views render state and send actions. They do not call Zerion or mutate
  SwiftData directly.
- Analytics remain outside `SyncEngine`.

## Source of truth

- Existing current positions remain authoritative for holdings.
- `PortfolioSnapshot` remains authoritative for all-account observed history.
- `AccountSnapshot` remains authoritative for a selected account from the
  earliest UTC day whose snapshot has `isFresh == true`.
- Zerion chart points may fill only the earlier selected-account period.
- Zerion P&L is an attributed provider estimate and is never presented as
  global Portu P&L.

## Local persistence and privacy

- Persist normalized numeric fields required by the feature.
- Never persist raw Zerion response bodies, authorization headers, API keys, or
  transaction corpora.
- Never log API keys or full wallet addresses.
- Editing account identity invalidates the old analytics scope.
- Account deletion removes only that account's provider analytics.
- Users can clear provider analytics without deleting holdings, local
  snapshots, historical asset prices, or another account's cache.

## External go/no-go

Before analytics are enabled by default:

1. Authenticate wallet chart, wallet-set chart, wallet P&L, wallet-set P&L,
   implementation-filtered P&L, and `no_filter` behavior using the minimum
   intended Zerion plan.
2. Verify meaningful Solana-only chart and P&L output and record unsupported
   protocol history.
3. Record quota limits and worst-case refresh cost including bounded `503`
   polling.
4. Decide explicitly that the minimum required plan is acceptable for Portu
   BYOK users.

If the plan dependency is unacceptable, ship the Value Change correction and
keep Zerion analytics disabled. A `402` screen is not an acceptable primary
feature outcome.

The current implementation environment has no `ZERION_API_KEY`, so this
authenticated gate cannot be claimed complete by fixture-driven tests.

## Delivery

1. Value Change terminology correction.
2. Core values, cache schema, chart adapter, bounded history, and FX splice.
3. P&L adapter, TCA workflow, and UI behind a local feature gate.
4. Lifecycle controls, diagnostics, documentation, and live verification.
