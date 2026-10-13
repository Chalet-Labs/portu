# Portfolio Valuation Behavioral Spec

## Terms

- **Token**: one `PositionToken` that has an asset. Its sync-time USD value is `usdValue` and its sync time is `syncedAt`. Tokens whose asset is gone are outside valuation everywhere.
- **Valuation input**: a token plus its **position context** (position id, position type, account id, chain, protocol). The model-to-value boundary emits it in two variants:
  - active accounts only, for dashboards
  - every account, for Accounts (S9)
  The module computes every aggregate from these inputs. No view groups or sums values.
- **Value**: a token's unsigned worth in USD.
- **Contribution**: the value signed by role. Totals sum contributions.
- **Valued token**: a token whose source is manual, live, close or sync.
- **Counted token**: a token with a positive role (supply, stake, LP token, balance) or the borrow role, **and** `amount > 0`. Rewards and `amount ≤ 0` tokens are not counted.
- **Display value**: a USD amount × the current USD-to-display rate.
  - Valuation, aggregates and the display filter all work in USD, so the dust threshold is compared in USD and never scaled.
  - The rate is applied once, in a single display step, after every aggregate and the filter are done.

## Inputs

### I1: Every price input is USD
- **Live book**: the USD book keyed by price ID (`AppFeature.State.livePricesUSD`).
- **Historical closes**: the latest **USD** daily close per price ID inside today's window (UTC today minus two days). Each close keeps its UTC day.
  - All production backfill writes USD rows (CoinGecko and Zerion). Rows in other currencies are ignored.
    - #71 once wrote display-currency rows, but any survivors are older than the two-day window, so the rule has no effect on real stores.
  - As today, the closes are empty when historical backfill is disabled.
  - Core builds closes from a currency-tagged Core close-row value type (price ID, UTC day, currency, price), projected from `HistoricalPricePoint` at the boundary.
- **Manual and sync values**: manual override prices are USD, and the sync-time `usdValue` is USD.
- **24h fractions**: the live 24h changes are merged over the historical ones.
  - A historical fraction comes from the USD closes of two **consecutive** UTC days.
  - Two latest closes that are not on consecutive days give no fraction.
- **Display rate**: the current USD-to-display rate. Closes are converted at this current rate, not at the historical rate of their day.

### I2: One source per input (end state after PR b)
- **End state:** views get historical closes from one environment value (USD, with days). No screen keeps a second price book for valuation.
- **Transitional (PR a only):**
  - `historicalDisplayPrices` and `appState.prices` (the display-currency live book) remain for the screens that PR (b) migrates.
  - A migrated screen reads only the USD inputs.
  - In PR (a) the Overview and Sidebar switch their historical 24h-change input to the USD consecutive-day fractions. Asset Detail's header reads the live changes only, and it moves to the merged fractions in PR (b) (S7).
- **PR (b) cleanup:**
  - It deletes `historicalDisplayPrices`.
  - It deletes `appState.prices` if no reader remains.
  - Manual entry and the debug `/state/prices` route read the USD book or the store directly.
  - It deletes `AppFeature.State.liveDisplayPrices`, the derived display copy of the live book. Its last reader is `/state/prices`, which computes `livePricesUSD × currentUSDToDisplayRate` in place instead. Decided 2026-10-13.

### I3: Price ID
- **CoinGecko ID**: the override CoinGecko ID, else the asset CoinGecko ID, else the identity-mapped CoinGecko ID. Each is normalized.
- **Price ID**: `TokenIdentityMappingFeature.priceID(coinGeckoId:onchainIdentity:)`, unchanged. It resolves in this order:
  1. a native-sentinel identity on an ETH-family chain: the native CoinGecko ID
  2. an onchain identity on a chain with a CoinGecko platform: the **onchain** price ID, even when a CoinGecko ID exists
  3. a chain with no CoinGecko platform: the CoinGecko ID if there is one, else the onchain price ID
  4. no onchain identity: the CoinGecko ID
- The module never tries another ID when the resolved one has no price. Solana contract case is preserved.
- A manual price makes the price ID irrelevant to the valuation.
- The **market price ID** (`TokenPricingOverrideFeature.marketPriceID`) resolves the same way but disregards a manual price: a manual price changes the value, not the coin. The S3 watchlist ignore rule uses it.

## Per-token valuation

### V1: Precedence
The rules are evaluated in order. The first rule that applies decides the value and its source.

1. **Ignored**: the asset's override has `isIgnored`. The value is 0 and the source is *ignored*. This beats `alwaysShow` and every other rule.
2. **No amount**: `amount ≤ 0`. The value is 0 and the source is *unpriced*. The token is not counted (Terms), so it never produces a row or a count. This matches today's `amount > 0` guards.
3. **Manual**: the override has a manual price > 0. The value is `amount × manual` and the source is *manual*.
4. **Live**: the live book has a price > 0 for the price ID.
   - If the price ID is onchain and the price fails V3, the token is *unpriced* with value 0. There is no fallback.
   - Otherwise the value is `amount × live` and the source is *live*.
5. **Newer-of**: there is no live price.
   - **Candidates:**
     - the **close**: a close > 0 for the price ID
     - the **sync value**: `usdValue != 0`
   - **Both present:** the close is chosen only when its UTC day is after the UTC day of `syncedAt`. Views have no intraday timestamp for a close, so on the same day the precisely timestamped sync value wins. A nil `syncedAt` sorts as oldest.
   - **One present:** that one is chosen.
   - **Implausible close:** if the chosen close has an onchain price ID and fails V3, the token is *unpriced*, the same as a failed live price. It does not fall back to the sync value. A close that loses to a newer sync is never checked.
   - **Source:** *close* (value `amount × close`) or *sync* (value `|usdValue|`).
6. **Unpriced**: otherwise. The value is 0 and the source is *unpriced*.

### V2: Contribution by role
- Positive roles contribute `+value`.
- Borrow contributes `−value`.
- Reward contributes **0**.
  - Its value is still computed, so a token-level row (S6, S7) may show it, marked as not counted.
  - It never enters an aggregate, a dashboard row, a slice or a hidden-balances summary.

### V3: Plausibility (onchain price IDs only)
- The reference is `|usdValue|`. A reference of 0 makes the price plausible.
- Otherwise the price is plausible when `amount × price / reference` lies in `[0.01, 100]`, inclusive at both ends. Both sides are USD.
- CoinGecko price IDs are never checked.

### V4: 24h change per token
- **Formula:** `contribution × p / (1 + p)`, where `p` is the merged fraction for the price ID.
  - It is exact when the valued price and `p` come from the same observation: a live price with its live change, or a close with the change between closes.
  - It is an estimate otherwise:
    - a live price with only a historical fraction
    - the *sync* source, where the provider's value is moved by the market fraction
- **Zero when:**
  - the source is manual, ignored or unpriced
  - the role is reward
  - there is no fraction
  - `1 + p ≤ 0`

### V5: Price, source and fraction of a row
- **Price.** Some rows show a unit price: the watchlist and the Asset Detail header. Token Settings shows no unit price, so it does not compute one. Decided 2026-10-13.
  - The price is Σ value ÷ Σ amount over the row's counted tokens that have a value.
  - When every such token shares one live or close price, this is exactly that price.
  - With no valued counted token, the row has no price.
- **Source.** The source of the row's **lead token**: the counted, valued token with the largest value.
  - Ties are broken in this order:
    1. source order: manual > live > close > sync
    2. the lowest asset ID string
    3. the lowest price ID string
- **Fraction.** The row's 24h fraction is the merged fraction of the lead token's price ID.
  - It is absent when the lead token's source is manual.
  - It is shown for live, close and sync. It describes the market move of the asset's price.

## Aggregates

### A1: Net total
- The net total is the sum of every contribution over active accounts.
- It includes every valued token: dust, sub-threshold borrows, and rows that a display filter hides.

### A2: Gross assets and debt
- **Gross assets**: the sum of the positive-role contributions.
- **Debt**: the sum of the borrow values, shown as a positive amount.
- Gross assets − debt = net total.

### A3: Summary cards (Overview, active accounts)
- **Idle**: the positive-role contributions in `idle` positions.
  - Rows: "Stablecoins & Fiat", the majors row and "Tokens & Memecoins", using today's category rules.
- **Deployed**: the positive-role contributions in every non-idle position.
  - Rows: Lending, Staked, Yield (farming and liquidity pools), and **Other** (vesting and other).
- **Debt**: one row, "Borrowed", holding the debt from A2.
- Card rows are fixed and are **not** display-filtered. An empty row shows 0.
- Idle + Deployed − Debt = net total. This holds with and without live prices, with borrows, and with vesting or other positions.

### A4: 24h change of an aggregate
- **Change:** the sum of its tokens' changes (V4). Every valued token counts; there is no dust filter.
- **Percentage:** `change / (total − change)`, shown only when the prior total `total − change` is **> 0**. Otherwise it shows "—".

### A5: Every aggregate comes from the module
- The module computes every section, group, card, account, platform, network, filter-sidebar and headline total.
- No screen reads a stored total for display.

### A6: Sync-time total
- The role-signed sum of the **raw** `usdValue` over every token that has an asset, whatever its amount, with no repricing and no ignore filter.
- Rewards count 0, as in SyncEngine.
- It is raw on purpose, so that it equals SyncEngine's `netUSDValue`. V1.5's sync source uses `|usdValue|`; the two differ only if a provider ever stored a negative `usdValue`.
- It is used for the Accounts tooltip (S9), for snapshot recording (N1, over non-ignored tokens), and as a reference.
- It equals `Σ Position.netUSDValue` whenever every token has an asset. Sync writes `netUSDValue` as this same signed sum, and every synced token has an asset.

### A7: Basis and scope per list (decided 2026-10-10)
"Total" means visible rows + capped remainder (F5) + hidden-balances line, unless the list is marked as exempt.

| List | Basis | Scope, and what its total equals |
|---|---|---|
| Overview headline and Sidebar header | net | portfolio: the net total |
| Summary cards | per card (A3) | portfolio: Idle + Deployed − Debt = net total |
| Idle Stables and Idle majors tabs | net (the tabs admit positive roles only, so net equals gross) | the tab's own subset |
| Borrowing tab | borrow values, shown positive | the tab's subset (Σ = debt over borrows in that tab's positions) |
| Key Changes tab | net (positive roles only, so net equals gross) | **exempt**: a top-20 selection (F5). Group total = Σ shown rows |
| Top Assets donut (both modes) | **gross** | portfolio: gross assets |
| Exposure summary | Spot total gross; Liabilities borrow values; Net total net | portfolio: Net total = net total |
| Exposure category table, Exposure asset table | each row has spot, liabilities and net | per table: Σ row spot = Spot total, Σ row liabilities = Liabilities, Σ row net = Net total (with that table's hidden sums per basis) |
| Assets, Platforms, Networks | net | portfolio: the net total |
| Health weight list (expanded) | net, rows are symbol + name groups with net > 0 only | portfolio: Σ of positive asset nets (= Σ floored values). The collapsed top-5 view is **exempt** (a preview) |
| Performance bottom panel | per asset | **exempt**: it lists changes, not current values. It hides rows through the filter, but has no line |
| All Positions sections and cards, filter sidebar | net | a section = Σ its cards; the "All" option = the net total |
| Accounts | net | per account; Σ over active accounts = the net total |
| Asset Detail holdings, per-chain breakdown and table | net | that asset |
| Watchlist | prices | **exempt**: it lists prices, not holdings |

## Display filter

The display filter applies **only** to the dashboard lists: the Overview tabs, the donut, the watchlist candidates and the Health weight list (S3), Exposure (S4), Assets / Platforms / Networks (S5), and Performance eligibility (S10).
- All Positions, Asset Detail, Token Settings and Accounts never hide rows and have no hidden-balances line.
- The summary cards are not filtered (A3).
- The filter never changes a total.

### F1: Classification
- **Input:** rows of any grouping (asset, slice, category, token) plus `TokenDashboardSettings`. There is no rate: everything is USD.
  - Each row carries the USD values of its tokens on three bases: gross (positive roles), debt (borrows) and net.
- **Which tokens build a list's rows** depends on the list's basis:
  - **the donut** (gross): positive-role tokens only. A borrow-only asset has no donut row and does not appear in the donut's hidden summary.
  - **the Borrowing tab**: borrow tokens only.
  - **Health**: counted tokens of both kinds, grouped per symbol + name as today. Only groups with net > 0 are kept as rows, so the hidden net sum is the floored sum.
  - **Idle tabs**: positive-role tokens, as today.
  - **every other list**, Exposure included: counted tokens of both kinds.
    - Exposure's category table and asset table are each one row set. Every row carries spot, liabilities and net.
    - Each table has its own statuses, hidden line and remainder. A borrow-only asset keeps its row.
- **Ignored tokens** contribute 0, and they do not enter statuses 3–5, which are evaluated over a row's non-ignored counted tokens.
- **Status** of a row, independent of the toggles. The first match wins:
  1. **ignored**: the row has at least one counted token, and every counted token is ignored. Example: an ignored supply next to another asset's reward.
  2. **notCounted**: the row has no counted token at all. Examples: reward-only, or amount 0.
  3. **unpriced**: every counted token is unpriced
  4. **dust**: the row's **filter value** is below the threshold (F2)
  5. **priced**
- **alwaysShow**: true when any of the row's assets has `alwaysShow`. An ignored asset's `alwaysShow` has no effect.
- **Filter value** of a row: the larger of the **constructed row's** gross and debt values, in USD, for every list.
  - The donut row holds only gross values. An asset with $0.99 gross and $1.01 debt is therefore dust on the donut, but visible on Exposure.
  - A protocol, chain or asset that is hedged by its own borrow is therefore not dust, even when its net is near 0. This covers a looped lending position on Platforms and an asset hedged on Exposure.
  - The row's displayed value and sums stay on the list's own basis.
- **Output:**
  - each row's status, alwaysShow flag and **visible** flag (F2)
  - a hidden-balances summary: the count, the count of unpriced rows, and the hidden **gross, debt and net** sums, all over the **same** hidden-row set
- Token Settings uses the status and the alwaysShow flag (S8). No screen re-derives the threshold rule.

### F2: Visibility (ordered)
1. **ignored** and **notCounted** rows are not dashboard rows: they are not visible and are not counted in the hidden summary.
2. A row with alwaysShow is visible.
3. An **unpriced** row is decided by `hideUnpriced` alone: hidden when it is on, visible when it is off. The dust rule never applies to unpriced rows.
4. A **dust** row is hidden when `hideDust` is on. Dust means the USD filter value is `< max(0, minimumDashboardValue)`. The threshold is a USD amount and is never scaled by the rate.
5. Every other row is visible.

Dust is judged on the **displayed row**, after aggregation. Two dusty tokens that form one row above the threshold stay visible.

### F3: The hidden-balances line
- A list ends with the line when N > 0 rows are hidden.
- The text is "+ $X" for a sum ≥ 0 and "− $X" for a negative sum.
- It reads "in N small balance(s)" when every hidden row is dust, and "in N hidden balance(s)" when any hidden row is unpriced.
- A list uses the hidden sum on its own basis. Exposure uses all three.
- When the donut's hidden gross sum is 0 (every hidden row is unpriced), the line appears as a legend row with no slice.
- Changing the threshold or a toggle changes the rows and the line. It never changes a total.

### F4: Shares
- **Where they exist:** Platforms, Networks, the donut, the Health weight list and the Asset Detail per-chain breakdown.
- **Definition:** a share is the row's value ÷ the list total, on the list's basis.
- **When shown:** only when the list is non-empty and its total is > 0. Otherwise each share shows "—".
- **Rounding:** displayed shares, including the capped remainder and the hidden line, sum to 100% by largest remainder (the AGENTS.md rule, decided 2026-10-12). Round each exact share to the nearest display step (0.1%, or 1% where a view shows whole percents such as the donut legend). Then move the residual one step at a time: a positive residual adds a step to the rows with the largest (exact − rounded) error, a negative one takes a step from the rows with the most negative error. Ties go to the larger absolute value, then the earlier row. Each row moves at most one step, so no displayed share is a step or more from its exact value. Example: one row at 95.2% and 120 rows at 0.04% each show 95.2%, 48 rows at 0.1% and 72 at 0.0%; the old residual-to-largest rule showed the large row at 100.0%.
- **Negative rows:** a negative row on a net list shows a negative share.
- **Not shares:** Exposure's "% of spot" figures are ratios. They are not forced to sum to 100%.

### F5: Capped lists
- **Ranking and remainder:** a list that shows only its top N ranks the visible rows. The rows beyond N go into an "Other" row whenever it is non-zero; today the donut has this row. The remainder is distinct from the hidden-balances line. Top N + Other + hidden line = the list's total.
- **Donut:**
  - Asset mode: top 5. Category mode: top 6. Each mode has an "Other" slice.
  - Ranking is by gross value, with today's tie-breaks.
- **Key Changes:**
  - Candidates are the F2-visible counted positive-role tokens with change != 0.
  - It shows the top 20 by |change|, with ties broken by symbol (today's rule).
  - It has no remainder and no hidden line, and is exempt in A7.
- **Health:** the collapsed view shows the expanded list's top 5 and is exempt. The expanded list obeys F3 and F4.
- **Watchlist:**
  - Held rows: the top N F2-visible assets by contribution > 0.
  - Watched coins that are not held are appended.
  - Exempt in A7.

## Screens

### S1: Overview headline and Sidebar header (PR a)
- Both show the net total (A1) and the 24h change (A4), through one module call.

### S2: Overview summary cards (PR a)
- Idle / Deployed / Debt, per A3. Debt takes the third slot, which #118 freed.
- Identity mappings apply. Today the cards read the raw `asset.coinGeckoId`.

### S3: Overview tabs, donut, watchlist and health (PR a)
- **Tabs:**
  - Rows show contributions. The Borrowing tab shows borrow values as **positive debt** (A2): its rows, group totals and 24h change are on the debt basis, and a rising debt is tinted as a loss. Decided 2026-10-11.
  - Idle and Borrowing tabs: group total = Σ visible rows + the group's hidden line. A group's 24h change also covers its hidden rows (A4).
  - A position group with at least one visible row ends with its own hidden line. A group with **no** visible row gets no card. Its rows go into one hidden line at the end of the tab, so nothing leaves the tab. Decided 2026-10-11.
  - Key Changes: per F5.
- **Donut:** gross basis, per F5. The hidden line adds a hidden-balances share.
  - A visible row with value 0 (unpriced, with hideUnpriced off) is a legend row with no slice.
- **Watchlist:**
  - Held rows show their V5 price × rate and their V5 fraction.
  - A watched coin that is not held shows its live price, else its latest close, × rate, plus its merged fraction.
  - Ignored assets are excluded from the held rows **and** from the watched coins. Decided 2026-10-12.
    - The user ignores an asset, not a coin. A watched coin is hidden only when at least one asset is priced under its ID and **every** asset priced under it is ignored, even when it is on the watchlist.
    - Priced under the ID: every asset whose CoinGecko ID (override applied) is that ID, and the asset of every valued token, ignored ones included, whose non-onchain market price ID (I3, identity mappings included) is that ID.
    - Ignored follows the override that applies to the asset (lowest override ID wins), as in valuation.
    - Example: native USDC and bridged USDC.e are both priced under `usd-coin`. Ignoring USDC.e keeps a watched `usd-coin`; ignoring both hides it.
    - A shown watched coin describes the preferred non-ignored asset whose CoinGecko ID is its ID. Only when every such asset is ignored (the coin shows through a held, non-ignored token, e.g. a mapped one) does it fall back to the preferred asset, as before.
- **Health:**
  - Rows are grouped per symbol + name, as today. A row's weight is its net contribution floored at 0, divided by the sum of the floored values.
  - The metrics (concentration, HHI, stablecoin ratio, asset count) cover **every** symbol + name group, hidden ones included, the way totals do. They use the floored values of the weights: a net-negative group has weight 0 and is not counted as an asset.
  - Identity mappings apply to the cards and Health as everywhere else. Their views gain a query for the mapping rows, which change rarely; that is not high-frequency observed state.
  - The expanded weight list applies the display filter, the hidden line and F4.
  - Plausibility, manual prices and mappings apply.
  - Ignored tokens are excluded.
  - `chainCount` counts the chains that have a valued, non-ignored counted token in an active account.

### S4: Exposure (PR b)
- **Summary:** a 2×2 grid:
  - **Spot total** (gross)
  - **Liabilities** (debt)
  - **Net total** (spot − liabilities = the Overview net total)
  - **Net exposure (excl. stablecoins)**, unchanged in meaning
- **Rows:** module values. Each table's hidden line shows that table's gross, debt and net hidden sums (F1).
- **Implausible prices:** an implausible onchain price shown with `hideUnpriced` off counts 0. Today it falls back to the sync value.

### S5: All Assets: Assets, Platforms and Networks (PR b)
- Rows are sums of contributions per asset, per protocol and per chain. They stop reading `Position.netUSDValue`.
- Each tab's total equals the Overview net total.
- Platforms and Networks gain the display filter and the hidden line, as dashboards under rule 3.
- For an asset with at least one counted token, the Assets row value equals the Token Settings row value. The one exception is an unpriced row: the Assets tab values it at 0, while Token Settings shows no value (U4).

### S6: All Positions (PR b)
- A card is Σ its tokens' contributions. A section is Σ its cards. A filter-sidebar option is Σ its cards.
- Token rows are signed:
  - a borrow is negative
  - a reward is shown as not counted
  - an ignored token is greyed, with an "Ignored" badge and no value
- No row is hidden.

### S7: Asset Detail (PR b)
- **Header:** the V5 price and its V5 fraction, from merged live and historical fractions. Today it reads live changes only.
- **Holdings and positions table:** both use contributions. The table stops adding rewards and stops showing borrows as positive.
- **Per-chain breakdown:** each chain shows its net amount and its net contribution. Shares follow F4 on the net basis, replacing today's positive-amount shares.
- **Ignored tokens:** greyed, with an "Ignored" badge and no value.
- **Charts:** the value, amount and price charts keep plotting recorded rows, ignored or not. Decided 2026-10-10.

### S8: Token Settings (PR b)
- Token Settings uses the **active-accounts** valuation input, like the Assets tab.
- Each position token is valued by the module. Nothing is netted before pricing.
- **A row:**
  - value: Σ its tokens' contributions. Following U4, an unpriced row shows no value, and a not-counted row shows its tokens' own value, muted, while counting 0.
  - source: V5
  - status: F1, plus alwaysShow
- Rows with no counted token (reward-only) show the status **notCounted**.
- A sync-only token is valued with the *sync* source.
- Mappings and closes apply.
- An ignored row is still listed, with status *ignored* and no value.
- The "Hide unpriced" subtitle changes to say it hides rows and never changes totals.

### S9: Accounts (PR b)
- A balance is Σ the contributions of that account's own tokens, **active or not**. It uses the all-accounts valuation input.
- A tooltip on the Balance cell shows the sync-time total (A6) as "Provider total at last sync".
- Σ of the active balances = the Overview net total.

### S10: Performance eligibility (PR b)
- The bottom panel's eligibility uses the module and the display filter, one row per asset.
- `PerformanceDataRequest` carries the USD live prices and the USD closes.
- Overrides are projected without the main actor.

### S11: Debug endpoint (PR b)
- **Existing route:** `/state/positions` is unchanged, including its raw per-position `netUSDValue`.
- **New route:** `/state/totals` returns two labelled totals over active accounts (or over one account when `accountId` is given):
  - `valuedTotalUSD`
  - `rawSyncTotalUSD` (A6)
- **Inputs:** the same as the views. The USD book and rate come from the store through a closure. The closes are fetched from the store with the I1 window and the backfill-enabled rule. Overrides and mappings come from the store too.
- **Wiring:** the route registers in `DebugEndpoints`, which has no store access. `DebugServer` therefore injects a `@MainActor` closure that returns the USD book and rate. The backfill flag is read from `UserDefaults`. Decided 2026-10-13.
- **Scope with `accountId`:** the all-accounts input, filtered to that account, so the route reconciles with the Accounts balance (S9) for an inactive account too. An unknown account gives 404; a malformed ID gives 400. Decided 2026-10-13.
- **`/state/prices`:** keeps its `prices` key in the display currency, computed in place as `livePricesUSD × currentUSDToDisplayRate`. It adds `pricesUSD` and `usdToDisplayRate`. Decided 2026-10-13.
- **Tests:** a characterization test pins the route.

### S12: Polling and backfill eligibility (PR a for polling, PR b for backfill)
- **Shared rule:** their value checks call the module, and their own selection rules stay. Ignored tokens are never candidates, which is today's rule.
- **Selection value:** the module value, or `|usdValue|` when the module value is 0 (`ValuedToken.selectionValue`). Polling ranks by it (`OverviewFeature.pricePollingIDs`); backfill uses it for eligibility (`HistoricalPriceBackfillFeature.shouldIncludeToken`) and keeps its own price-ID ordering.
- **Polling:**
  - Overview keeps today's rank-by-value top N plus the watchlist. Exposure keeps its own rule: no ranking, no cap and no watchlist. It polls a counted, non-ignored token with a price ID when the token is in a visible row of the Exposure asset table, or when its source is *sync* or *unpriced* (for recovery). Manual, reward and `amount ≤ 0` tokens are never polled. Decided 2026-10-13.
  - A token is a candidate while it is in a visible row (F2) of the net asset-row list, which holds every token the tabs, Key Changes, the donut and the watchlist show, or of the Health list. Outside every such row, only the branch below for tokens with no usable price keeps it. Category slices, the headline, the cards and the hidden line never make a token a candidate.
  - Two copies exist: Overview's (PR a) and Exposure's `dashboardPollingPriceID`, which migrates with Exposure in PR (b).
  - The branch that keeps unpriced onchain IDs in the set stays. A token with an implausible onchain live price stays ranked by its sync value and stays polled, so it can recover.
  - Its ranking semantics belong to #101.
- **Backfill:** it keeps today's candidate rules, and it values tokens over an empty market, as it effectively does today. No production caller passes a price book, so today's value is already USD: manual price × amount, else `usdValue`. The candidate, source and identity-resolution sets therefore do not change. The threshold is unscaled USD. Decided 2026-10-13.
- The PR lists the marginal change in the polled and backfilled sets.

## Snapshots (PR b, separate commit)

### N1: Ignore-aware recording
- `createSnapshots` fetches the `TokenPricingOverride` rows.
- From now on, ignored assets are excluded from `PortfolioSnapshot`, `AccountSnapshot` and `AssetSnapshot`.
- **Totals:** portfolio and account totals become the A6 sum over non-ignored tokens. SyncEngine no longer reads `netUSDValue`.
- **Deployed:** the portfolio deployed value includes vesting and other positions, matching A3.
- **Unchanged:** the stale-account and partial-sync freshness handling.

### N2: Ignore-aware reading
- **Filtered readers:** the multi-asset `AssetSnapshot` readers leave out the assets that are ignored now, including rows recorded before the asset was ignored:
  - the Performance fetcher: category chart, bottom panel, estimate
  - the Overview value-chart estimate
- **Limit-1 "earliest" probes:** they skip ignored assets inside the fetch, either with a predicate on `assetId` or by fetching in order until a non-ignored row turns up. A test against an in-memory store pins the chosen approach.
- **Chosen approach (decided 2026-10-13):** a predicate that excludes the ignored IDs, `!ignoredIDs.contains($0.assetId)`, on the scalar `assetId`. It is used by the windowed reader and both probes, and `ignoredIDs` is captured as an `Array<UUID>`.
  - Tests pin it on an in-memory store and on one disk-backed store, each with an empty list and with thousands of IDs.
  - If a large list fails, the windowed reader filters in Swift after the fetch, and the probes page in timestamp order.
- **Not filtered:** Asset Detail's charts (S7).
- **Un-ignoring:** the old rows become readable again. Nothing is backfilled.
- **The step at the join (accepted 2026-10-13):** N2 filters the estimated segment, but N3 keeps the recorded totals. A holding that is ignored now therefore drops out of the estimate and stays in the recorded series it joins, so the chart can step at the join.

### N3: History is not rewritten
- Existing `PortfolioSnapshot` and `AccountSnapshot` rows keep their values.

## Deletions

### X1: The duplicates are deleted
- **Deleted outright:**
  - `AssetValueFormatter` pricing and `PositionGroupValue`
  - the `AssetDetailFeature` valuation and `PositionTokenEntry`
  - `OverviewSummaryCardsFeature.visibleToken`
  - `OverviewFeature.portfolioTotalDisplayValue`, `resolvedValue` and `passesDashboardThreshold`
  - both plausibility copies: `OverviewPositionPricing.isPlausible` and `TokenSettingsFeature.isPlausible`
  - the six `normalizedThreshold` copies
- **Price-ID normalization:** the duplicated helpers go. These stay:
  - `OnchainTokenIdentity.normalizedHistoricalPriceID`
  - `TokenIdentityMappingFeature.normalizedHistoricalPriceID` and `normalizedProviderID`
  - the asset identity keys, which are not price IDs: `SyncEngine.normalizedUpsertKey` and `AssetLookupCache.normalizedLookupKey`
- **Other pricing kernels:**
  - `TokenSettingsFeature.resolved*`, `isDashboardEligible` and `dashboardAdjustedToken`
  - `OverviewPositionPricing.tokenValue`, `change24h` and `changeReferenceValue`
  - `OverviewPriceChangeFeature.isDashboardEligibleForChange` (replaced by F2 and F5)
  - `ExposureFeature.dashboardResolvedValue`
  - `PortfolioHealthFeature.resolveValue`
  - the `AllAssetsFeature.aggregateRows` pricing branch
- **Overview-file price helpers:**
  - `latestCloses`, `latestPrices`, `changes24h` and `mergedChanges24h` are replaced by their Core versions.
  - `mergedPrices` has no replacement. V1.5 forbids a merged book, so it is deleted when its last PR (b) caller goes.
- **Test-only legacy overloads.**
- **Timing:** each duplicate is deleted together with its last caller. PR (a) deletes the Overview ones and the polling copies. PR (b) deletes the rest.

## Gates

### G1: Pricing arithmetic
- **Patterns:** `rg` over `Sources/Portu/Features/` finds none of these outside module calls and the allowlist:
  - `amount \*`
  - `\* .*[uU][sS][dD]ToDisplayRate`
  - `prices\[`
  - `usdValue \*`
  - `[pP]lausib`
  - `normalizedThreshold`
- **Allowlist** (listed in the PR):
  - time-series math: `HistoricalPortfolioEstimator`, the Performance series (including `ProviderPortfolioHistory`), `AssetPriceChart`, and the backfill `snapshotValue` over `AssetSnapshot` rows
  - `ManualPositionPricing` and `AddPositionSheet`, the manual-entry write path. PR (b) moves the sheet to the USD book. `ManualPositionPricing` then takes the USD price, so no display price and no rate round trip remain; the sheet disables Add for an amount ≤ 0. Decided 2026-10-13.
  - display formatting of a module result
- **Supplementary sweep:** the PR also lists the hits of `[aA]mount\)?\s*\*`, which the case-sensitive `amount \*` misses.

### G2: `netUSDValue`
- `Position.netUSDValue` is **written** by SyncEngine and by the manual-entry path.
- After PR (b) its only **read** is the debug `/state/positions` raw value. In PR (a), SyncEngine's snapshot sums still read it; N1 removes them.
- **Search:**
  1. The scoped regex `rg -n '(\bpos|\bposition|\$0|\$1)\.netUSDValue' Sources/` lists the candidate reads.
  2. A bare `rg -n netUSDValue Sources/` is then reconciled by hand. Every hit must be a write, the debug raw read, or a listed collision.
- **Name collisions** the PR lists (not `Position` reads):
  - `StagedPosition.netUSDValue`
  - `HistoricalEstimateSnapshotEntry.netUSDValue`

  PR (b) removes the two other collisions: the `NetworksTab` tuple and the Token Settings aggregate.

### G3: Verification gate (#116)
- `just test-packages`
- `just generate`, then the full Xcode scheme test
- `just format-check`
- `just lint-strict`
- `just generate` + `just debug-run` for the launch check, instead of `build_and_run.sh`, because of its signing side effect

### G4: Manual reconciliation (after PR b)
- On the real store, with the same filter settings: Overview total = Exposure Net total = Σ active Accounts balances.

## Tests (RED first)

### T1: PortuCore specs (`swift test`)
- **Price ID:**
  - A token with a CoinGecko ID **and** an ethereum identity resolves to the onchain ID and is plausibility-checked.
  - The live-CoinGecko fixture has no onchain identity.
  - Also: a native sentinel, a no-platform chain with an override, and an identity mapping.
- **Precedence:**
  - manual
  - live CoinGecko
  - live onchain
  - an implausible live onchain price → unpriced
  - an implausible chosen onchain close → unpriced
  - an implausible close that loses to a newer sync → the sync value
  - ignored
  - ignored + alwaysShow → ignored
  - amount 0 and a negative amount → unpriced, not counted, no row
  - borrow
  - reward
  - `usdValue == 0` → no sync candidate; plausible
  - plausibility at the ratio bounds 0.01 and 100 (inclusive), just outside them, and with reference 0
- **Newer-of:**
  - a close on a later day wins
  - a sync on the same or a later day wins
  - only a close
  - only a sync
  - neither → unpriced
  - a nil `syncedAt` loses to a close
- **Divergence:**
  - a section = Σ its cards
  - a manually priced token has the same value on the Positions path and the Overview path
  - Idle + Deployed − Debt = Total, with and without live prices, with borrows, and with vesting/other
  - a negative net portfolio (debt > gross)
- **Filter:**
  - With hideDust on, a $0.80 token and a $0.50 borrow are hidden but counted.
  - With rate 0.5 and threshold 1, a $0.80 token is dust and a $1.50 token is visible. The threshold is USD.
  - A row mixing an ignored supply with another asset's reward is *ignored*. It is not dust and not in the hidden summary.
  - A reward-only row is *notCounted*.
  - A borrow-only asset keeps its Exposure row. Its liabilities count in Σ row liabilities.
  - A row with $0.80 supplied and $1,000 borrowed is visible on Exposure under hideDust.
  - An asset with $0.99 gross and $1.01 debt is dust on the donut and visible on Exposure.
  - A dust asset inside an above-threshold category: it is hidden on the Exposure asset table while its category row stays visible. On both tables, visible + hidden equals the same three totals.
  - Health groups the same symbol held as two assets into one row.
  - With no positive-net group, Health has no rows and shows "—" shares without crashing.
  - A hedged protocol row ($50,000 gross, $0.80 net) is not dust on Platforms.
  - A borrow-only asset has no donut row and is not in the donut's hidden summary.
  - A net-negative asset has no Health row. Health visible + hidden = Σ of positive nets when such an asset is present.
  - Changing the threshold moves rows, never the total.
  - An unpriced row contributes 0.
  - With hideUnpriced off, hideDust on and threshold 1, an unpriced row is **visible** and the unpriced count is 0.
  - The hidden summary gives the count, the unpriced count, and the gross/debt/net sums.
  - Visible + remainder + hidden = total, for a gross list, a net list and Exposure's three bases.
  - Two dusty tokens forming one visible row.
  - A reward-only asset → notCounted, no dashboard row.
  - An Exposure row with $1,000 supplied and $1,000 borrowed is not dust.
  - Ignored + alwaysShow → not a dashboard row.
- **Capped lists:**
  - The donut top N + Other + hidden share = 100%.
  - The Key Changes selection and its cap.
  - The Health weights with more than 5 assets: the expanded list sums to 100%.
- **Shares:**
  - Rounding with a hidden share.
  - An empty list, a zero total and a negative total each show "—".
- **24h:**
  - the exact formula
  - manual, ignored, unpriced and reward give 0
  - `1 + p ≤ 0`
  - the aggregate percentage, including a prior total of 0 and a negative prior total → "—"
  - a historical fraction only across consecutive days
  - a live price combined with only a historical fraction (the estimate case of V4)
- **V5:**
  - the price with mixed sources
  - no price when nothing is valued
  - the lead-token tie-break
  - no fraction for a manual lead
- **Units:**
  - A non-USD rate is applied once.
  - Plausibility compares USD with USD.
- **Closes:** built from mixed-currency close rows, USD only; empty when backfill is disabled.
- **Sync-time total:** Σ signed `usdValue`.

### T2: App-level characterization tests
- **Seams first:**
  - Each screen group gets a pure entry point that its **production view calls**.
  - The entry point takes the valuation inputs (with position context) from day one.
  - It is added reproducing today's numbers, so the target compiles. For the stored-total screens that means the A6 signed-`usdValue` sum, which equals `netUSDValue` in production.
  - Then the failing tests go in. Run `just generate` after adding test files.
- **What they assert:** each test feeds one fixture portfolio and asserts the **same per-token value** on every path, plus each list's A7 identity.
- **PR (a):**
  - the headline, cards, tabs, donut, watchlist, health and Sidebar
  - the polling candidates:
    - an implausible-live token is still ranked by its sync value and is still polled
    - an ignored token with a large `usdValue` is not polled
- **PR (b):**
  - Exposure: a stablecoin-heavy fixture and a hedged-asset fixture; Net total = the headline
  - Assets, Platforms and Networks
  - All Positions
  - Asset Detail: the per-chain breakdown with borrows
  - Accounts: an inactive account with a non-zero balance
  - Token Settings: equals the Assets row for counted assets; a notCounted row
  - Performance eligibility
  - backfill eligibility
  - `/state/totals`
- **Scope reconciliation (PR b):**
  - Platforms total = Networks total = Σ active Accounts = Exposure Net total = Overview total.
  - Each All Positions section = Σ its cards.

### T3: Snapshot specs (PR b, written before the recording change)
- A sync with an ignored token records the portfolio, account and asset totals without it.
- Deployed includes vesting/other.
- An `AssetSnapshot` series leaves out an asset ignored after its rows were recorded.
- Un-ignoring brings the rows back.
- The limit-1 probes skip ignored assets.
- Existing `PortfolioSnapshot` and `AccountSnapshot` rows are not rewritten.
- Partial-sync freshness is unchanged.

### T4: Ignored display
- An ignored token is absent from dashboard rows, slices and hidden summaries.
- It is greyed with an "Ignored" badge and no value on All Positions and Asset Detail.
- It contributes 0 to every total.

## PR (b) decisions (2026-10-13)

The PR (b) description lists the commits in order and every intentional number change.

### Decided by the user
- **Manual entry:** see G1. `ManualPositionPricing` takes the USD price, and Add is disabled for an amount ≤ 0.
- **The hidden line in tables** is the last table row:
  - Exposure: its spot, liabilities and net cells hold the table's hidden gross, debt and net.
  - Platforms and Networks: it carries its share, so the shares sum to 100%.
  - Assets tab: it shows only while the search box is empty. Search never changes the line's numbers.
- **The Asset Detail header:**
  - A held asset follows V5. With no valued counted token, for example an implausible onchain price, it shows no card.
  - An asset with no counted, non-ignored token shows the market quote: the live price, else the latest close, under its market price ID (`MarketPrices.quote`).
- **Token-level rows** on All Positions, Asset Detail and Token Settings:
  - A reward or zero-amount token shows its value muted, tagged "Not counted".
  - A counted, unpriced token shows an "Unpriced" caption and no value.
  - An ignored token is greyed, with an "Ignored" badge and no value.
  - Token Settings gains a Not counted badge, a count and a filter entry.

### Decided in implementation (veto in review)
- **One shared valuation context.** `ValuationContext`, `ValuationPriceInputs` and `ValuationSources` live in `Features/Shared` and replace the Overview-named types. Each screen adds its own methods to the shared sources type.
- **`TokenDashboardSettings.showAll`:** lists that never hide rows use it, whatever settings the context carries.
- **A token-level row state on `ValuedToken`,** in this precedence: ignored, then notCounted, then unpriced, then counted.
- **`TokenPricingOverrideSnapshot.init(_:)` and `TokenIdentityMappingSnapshot.init(_:)` are nonisolated.** Models are read only on the actor that owns their context.
- **Per-asset rows are keyed by `assetId`** on Exposure, Assets, Token Settings and Performance. Overview keeps its price-ID + symbol key.
- **Exposure:**
  - Liabilities show as a positive amount, on the card and in the row cells (A2).
  - "% of spot" shows "—" when Spot ≤ 0.
  - The Assets pill counts visible rows.
  - The hidden line's first cell reads "N small balances" (all dust) or "N hidden balances". Its amounts sit in the spot, liabilities and net cells, shown with cents, and it has no "% of spot".
- **Platforms and Networks:**
  - "# Positions" and "# Networks" count counted, non-ignored tokens.
  - A platform's name is its lowest non-nil `protocolName`. A platform with none shows its protocol ID; it used to show "Unknown", which could repeat across rows.
  - Ties break by name, then by key.
  - No total row is rendered.
  - The hidden line has its label in the first cell, its value, and its share in the Share cell. Its count cells are empty.
- **Assets tab:**
  - The clock badge marks the *sync* source only, and a missing price shows "—". The badge is labelled "Sync-time price" for VoiceOver.
  - CSV exports the visible rows, with an empty cell for a missing price.
  - The hidden line's label spans Symbol and Name. Only its Value cell is filled.
- **Token Settings:**
  - Its status is `RowStatus`, with `alwaysShow` as a separate flag.
  - It gains a *close* source.
  - The manual-price count and filter read the override.
  - An ignored row shows "—" as its source, as does a not-counted row (V5 gives neither a source).
  - An ignored asset's Ignored badge, no-value rule, count and filter win over its F1 status, so an ignored reward-only asset counts as Ignored, not Not counted.
  - Rows sort by value, descending. Rows with no value (ignored, unpriced) come last. Ties break by symbol, then asset ID.
  - The view builds its context with `ValuationContext.activeAccounts` from its own override and mapping queries, rather than through `ValuationSources`. It already owns the override query and the dashboard settings for its writers.
  - `SettingsView` mounts `HistoricalPricesProvider`, so the Settings window sees closes (S8). Until the I2 cleanup strips the provider's display-currency work, every Settings tab pays for it.
- **Accounts:** the tooltip shows on every account, converted at the current rate.
- **Asset Detail:**
  - Active accounts only.
  - Token rows sort by contribution descending, then account name, then token ID.
  - The account count is the distinct `accountId`s.
  - Total Amount excludes ignored tokens.
- **Performance:** the request carries `livePricesUSD` and the USD closes, still read inside `.task`.
- **Price-ID normalization:** every duplicate routes through the Core helpers. The scope extends past `Features/` to:
  - PortuNetwork's `PriceService.fetchHistoricalPrices` and `CoinGeckoDTO` (both trim, lowercase and drop empties, as `normalizedProviderID` does)
  - `HistoricalBackfillPriceSource.hash`
  - the `TokenIdentityMapping` model copy

  `ZerionChainMapping` normalizes a chain, not a price ID, and stays.
- **Manual-entry price key:** the asset's CoinGecko ID is normalized with `TokenIdentityMappingFeature.normalizedProviderID` before the USD book lookup.
- **The Core API is tightened** once PR (b)'s consumers exist:
  - `public internal(set)` on the fields of `ValuationTotals`, `HiddenBalances` and `SummaryCards` (nested `Idle`/`Deployed` included), so Core can still mutate them while the app only reads.
  - The memberwise inits of `ValuationTotals` and `ListShares` become internal.
- **Out of scope** (listed in the PR):
  - the drift of the sidebar type labels
  - `TokenRole.signed` visibility
  - the Asset Detail chart key ignoring identity mappings
  - Performance `priceChanges` ignoring mappings
  - backfill's raw `manualPriceUSD != nil` check
  - `computeDiversificationMetrics` re-summing its weights (a follow-up for #123/#124)
