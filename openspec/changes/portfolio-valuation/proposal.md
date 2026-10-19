# Portfolio Valuation

## What

One pure valuation module in PortuCore, `PortfolioValuation`, decides what every
token is worth. Every screen that shows a **current** value switches to it, still
computing in the view; #124 later moves that computation into the read model.

Issue: #122 (epic #116). Type: **Behaviour**. Displayed numbers change on purpose
wherever screens disagreed today. The PR descriptions list every change, one line
per screen.

## Why

At least six slightly different valuation policies exist today. They differ in:

- override precedence (manual price, live price, historical close, sync-time value)
- the plausibility check on onchain live prices (two copies with different amount guards)
- the dust threshold (six `normalizedThreshold` copies)
- price-ID normalization (several trim/lowercase copies)
- whether a stored position total (`Position.netUSDValue`) or token-level values are used
- ignore handling (Accounts, Platforms, Networks and All Positions count ignored tokens)

As a result:

- An All Positions section total can differ from the sum of its cards.
- A manually priced token has one value on Positions and another on Overview.
- Platforms, Networks and Accounts read the sync-time `Position.netUSDValue`, while
  Overview revalues tokens live.
- The Overview headline drops dust (including small borrows) inside the total.
- A historical close always beats the sync-time value, however old the close is.

## Decisions

The five valuation rules were decided on 2026-09-30 to 2026-10-04 (D4 in
`.claude/files/implementation-plan-2026-09-30.md`, reproduced in issue #122).
The implementation decisions below were made on 2026-10-10:

1. **Two PRs.**
   - (a) This OpenSpec change, the PortuCore module and its specs, the price-input
     plumbing, and the Overview and Sidebar screens (including the Idle /
     Deployed / Debt cards). Uses `Refs #122`.
   - (b) Exposure, All Assets, All Positions, Asset Detail, Accounts, Token
     Settings, the Performance eligibility step and the debug endpoint. Then, in a
     separate commit, the ignore-aware snapshots. Uses `Closes #122`.
   - Between (a) and (b) the screens still disagree, which is no worse than today.
2. **USD inside the module.** Every input price is USD: the live book
   (`AppFeature.State.livePricesUSD`), USD historical closes (all production backfill
   rows are USD), manual override prices and the sync-time `usdValue`. The module converts
   to the display currency once, with the current USD-to-display rate. This removes
   the display-vs-USD unit mismatch in today's plausibility check.
3. **Per-list reconciliation basis.**
   - The Top Assets donut and the Exposure spot total reconcile to **gross assets**:
     positive roles only.
   - The headline, summary cards, position tabs, Platforms, Networks, Accounts,
     All Positions and Asset Detail reconcile to the **net** total.
4. **The provider-reported last-sync total** moves into a tooltip on the Accounts
   Balance cell.
5. **The 24h change is exact**: `value × pct / (1 + pct)`, measured against the price
   24h ago. Today's `value × pct` overstates the change by a factor of `(1 + pct)`.
6. **Exposure gets a 2×2 summary.** The cards are Spot total, Liabilities, Net total and
   Net exposure (excl. stablecoins). The Net total equals the Overview total, so the
   reconciliation in the acceptance criteria can be read straight off the screen.
7. **Asset Detail's charts stay unfiltered.** An ignored asset's own value, amount and
   price charts keep plotting its recorded rows. Rule 2 governs here. The issue
   contradicts itself on this point, and its Task names only the Performance fetcher
   and the estimate sources.
8. **Implementation calls**, each listed in the spec so it can be vetoed in review:
   - "Sync value present" means `usdValue != 0`.
   - A close beats the sync value only on a later UTC day.
   - A chosen onchain close that fails the plausibility check leaves the token unpriced,
     the same as a failed live price.
   - Rewards count as 0.
   - Dust is judged per displayed row.
   - Ignored tokens never appear in the hidden-balances line.
   - `amount ≤ 0` counts as unpriced.
   - Polling and backfill eligibility read their values from the module but keep
     their own selection rules.

## Scope

### In scope

- The `PortfolioValuation` module: price resolution, the newer-of fallback, signed
  values by role, totals and the 24h change. Plus a separate display filter that
  returns the hidden-balances summary.
- Converging every current-value screen on the module.
- The Debt summary card, and the "Other" row in Deployed.
- Ignore-aware snapshot recording and `AssetSnapshot` reading.
- Deleting the duplicated valuation code listed in the spec.

### Out of scope

- Moving computation out of the views into a read model (#123, #124).
- Recorded values in time-series charts (Performance charts, the Overview value
  chart, Asset Detail's charts).
- The polling ranking semantics and polling-ID selection rules (#101). Spec S12:
  polling keeps its rules, but its value checks call the module, with today's
  `|usdValue|` fallback.
- Removing `Position.netUSDValue` from the model (backlog).
- Live-price staleness: the live book has no per-ID timestamp. Any live entry
  counts as current.
- The backfill candidate rules. Spec S12: they stay, but their value check calls the
  module, with today's `|usdValue|` fallback, so the value is now USD throughout.

## Architecture

- `PortfolioValuation` lives in `Packages/PortuCore/Sources/PortuCore/Valuation/`, next to
  the value types #121 moved there. It is made of pure functions over `Sendable`
  value types, imports Foundation only, and has no SwiftData, SwiftUI or TCA.
- The model-to-value boundary stays in `ValuationSnapshots+Models.swift`. Any input
  the Performance `@ModelActor` needs gets a nonisolated projection.
- Views receive USD inputs:
  - The live USD book comes from `AppFeature.State.livePricesUSD` (or its `AppState`
    bridge).
  - The historical USD closes come from a SwiftUI environment value that
    **replaces** `historicalDisplayPrices`, so there is one source of truth rather
    than two keys.
- Views do not gain new high-frequency observed state where they can avoid it. Overview
  re-renders cost about 5 s in Debug, so each Overview input is a swap, not an
  addition. In PR (b), the screens that read stored totals today (Accounts,
  Platforms, Networks, All Positions) must read the live USD book every tick,
  because S5, S6 and S9 need token-level values. Each computes one valuation per
  body pass. A stall-probe A/B against master is the check.

## Risks

| Risk | Mitigation |
|---|---|
| Users see numbers change | Each PR lists every intentional change, one line per screen. |
| PR (a) leaves Overview disagreeing with Accounts until (b) | Accepted in the issue: no worse than today. |
| Characterization tests that fail to compile break the whole PortuTests target | Add the per-screen seams with today's behaviour first, then the failing assertions. |
| Grep gates produce false positives (`netUSDValue` name collisions) | The gate regex is scoped to `Position` reads, and the PR lists the colliding names. |
| Two inputs coexist during the PR (a)→(b) transition (`historicalDisplayPrices` and `appState.prices` next to the USD inputs) | Migrated screens read only the USD inputs. PR (b) deletes the old ones. Spec I2 states this transitional rule. |
| Values that polling ranks by now follow V1, so the polled set can change at the margin | The ranking semantics are unchanged and stay #101's. The PR lists this change. |
| Screens that read stored totals start reading the live book every tick (PR b) | One valuation per body pass; a stall-probe A/B against master accepts a median regression of 10% at most. |
| N2 filters the estimated segment but N3 keeps the recorded totals, so the value chart can step at the join | Accepted 2026-10-13; the PR notes it. |
