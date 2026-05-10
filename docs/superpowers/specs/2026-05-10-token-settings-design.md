# Token Settings and Dashboard Eligibility Design

## Summary

Portu should keep low-value, zero-value, and unpriced tokens available for review without letting them slow down heavy dashboard screens. Exposure, Overview, and Performance should aggregate only dashboard-eligible tokens by default. A new Token Settings screen in Settings will provide a search-first workflow for inspecting tokens, setting manual prices, mapping price sources, and hiding spam or dust.

## Goals

- Keep Exposure and other heavy dashboards responsive even when a wallet sync returns 1,000+ dust or unpriced tokens.
- Preserve all synced token data so users can search, inspect, and correct pricing.
- Give users app-wide controls for the minimum displayed dashboard value and token visibility.
- Keep provider-synced asset metadata separate from user pricing and visibility intent.

## Non-Goals

- Do not delete synced zero-value tokens.
- Do not build per-account token overrides in this version.
- Do not replace the existing portfolio category settings.
- Do not add a new external price provider beyond existing CoinGecko ID mapping and manual prices.

## Defaults

- Minimum dashboard value: `$1.00`.
- Hide unpriced tokens from dashboards: enabled.
- Hide dust tokens below the threshold from dashboards: enabled.
- Zero-amount tokens are excluded from dashboards.
- Unpriced tokens with a non-zero amount remain searchable in Token Settings.

## Dashboard Eligibility

A token is eligible for heavy dashboard aggregation when all of these are true:

- It belongs to an active account and active position.
- Its amount is greater than zero.
- It is not explicitly ignored by the user.
- It is not a reward token unless the target feature explicitly includes rewards.
- It has a resolved value at or above the configured minimum dashboard value.

Manual user choices can override the default threshold:

- `alwaysShow` includes a token in dashboards even below the threshold.
- `isIgnored` excludes a token from dashboards and normal asset lists.

Unpriced tokens should not contribute to portfolio totals. If a user sets a manual price or maps a CoinGecko ID, they become eligible once the resolved value meets the threshold or `alwaysShow` is set.

## Token Settings Screen

Add a new Settings tab named `Tokens`.

The screen is search-first and limited to a maximum of 100 displayed rows per query/filter. It should never render every synced token at once.

Filters:

- All
- Unpriced
- Below Threshold
- Ignored
- Manual Price
- Mapped Price Source

Rows show:

- Symbol and name
- Network
- Net amount
- Resolved value
- Pricing source: Live, Sync-time, Manual, or Unpriced
- Visibility status: Visible, Dust, Ignored, or Always Show

Actions:

- Set manual USD price.
- Map or override CoinGecko ID.
- Ignore token.
- Always show token.
- Clear overrides.

The settings page should also show compact counts for hidden dust, unpriced, ignored, and manually priced tokens.

## Data Model

Add a user-owned override model rather than storing user intent directly on `Asset`.

Suggested model: `TokenPricingOverride`.

Fields:

- `id`
- `assetId`
- `manualPriceUSD`
- `coinGeckoIdOverride`
- `isIgnored`
- `alwaysShow`
- `notes`
- `createdAt`
- `updatedAt`

The override key should reference `Asset.id`. Provider sync can keep updating `Asset` metadata without overwriting user choices.

## Data Flow

1. Sync persists assets, positions, and tokens as it does today.
2. A shared eligibility resolver combines `PositionToken`, `Asset`, live prices, and `TokenPricingOverride`.
3. Heavy dashboards call the resolver before aggregation so excluded tokens are filtered out before row construction.
4. Token Settings uses a lightweight query path and applies a hard display limit of 100 rows after search/filtering.
5. Editing a token override updates SwiftData and immediately affects subsequent dashboard aggregation.

## Performance Requirements

- Exposure must not instantiate or aggregate 1,000+ irrelevant dust/unpriced rows by default.
- Token Settings must cap visible rows to 100 and present a clear message when more matches exist.
- Shared filtering logic must be testable without rendering SwiftUI.
- Search and filter behavior should use deterministic sorting so repeated queries are stable.

## Testing

- Unit tests for dashboard eligibility:
  - zero amount excluded
  - ignored excluded
  - unpriced non-zero excluded by default
  - below `$1.00` excluded by default
  - `alwaysShow` overrides threshold
  - manual price makes unpriced token eligible when value is at least `$1.00`
- Unit tests for Token Settings row shaping:
  - search limits to 100 rows
  - filters classify unpriced, dust, ignored, manual price, and mapped price source
  - counts remain correct when displayed rows are limited
- Render smoke tests for the Token Settings tab.
- Existing Exposure render tests should continue to pass with a large number of hidden tokens.
