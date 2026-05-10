# Configurable Portfolio Categories Design

## Summary

Portu should replace the current fixed `AssetCategory.major`-style taxonomy in user-facing portfolio analysis with app-wide, user-configurable portfolio categories. The default category set should be opinionated enough to make Exposure useful out of the box, but users must be able to redefine what categories mean by assigning token symbols globally.

Version 1 uses purely global symbol rules. A normalized token symbol maps to one category everywhere in the app. Asset-specific overrides are intentionally out of scope for now.

## Goals

- Make BTC, ETH, and SOL first-class default portfolio categories instead of hiding them under a vague Major bucket.
- Preserve useful defaults for DeFi, Meme, Privacy, Fiat, Stablecoins, and Other Tokens.
- Let users create, rename, delete, reorder, and reassign categories app-wide.
- Use the same category resolver across Exposure, Overview, All Assets, Performance, Portfolio Health, and Asset Detail.
- Let category changes apply retroactively to charts and analysis because categories are user classification rules, not historical market values.

## Non-Goals

- Do not add SUI as a default category.
- Do not add asset-specific category overrides in v1.
- Do not introduce backend sync or telemetry.
- Do not change account, position, price, or provider sync semantics beyond category classification.
- Do not make every historical snapshot store a frozen category display name.

## Default Categories

The seeded default categories are:

- BTC
- ETH
- SOL
- DeFi
- Meme
- Privacy
- Fiat
- Stablecoins
- Other Tokens

Default categories are user-editable after seeding. `Other Tokens` is the required fallback category in v1. It may be renamed or reordered, but it cannot be deleted.

## Default Symbol Rules

The initial symbol assignments are:

- BTC: BTC, WBTC, TBTC, CBBTC
- ETH: ETH, WETH, STETH, WSTETH, RETH, CBETH, OSETH, SFRXETH
- SOL: SOL, WSOL, MSOL, JITOSOL, JUPSOL

Rules compare symbols after normalization: trim whitespace, uppercase, and remove hyphens, underscores, and spaces. A symbol can belong to only one category at a time.

## Data Model

Add two persisted SwiftData models in PortuCore.

`PortfolioCategory` represents a user-visible category:

- Stable `id`.
- `name`, shown throughout the app.
- `sortOrder`, used for settings and deterministic display.
- `semanticRole`, a small system-facing role such as normal, stablecoin, fiat, or fallback.
- `isSystemRequired`, used for required categories like fallback.

`CategorySymbolRule` represents a global symbol assignment:

- Stable `id`.
- Normalized `symbol`.
- Relationship to `PortfolioCategory`.

The existing `Asset.category: AssetCategory` remains during migration as a legacy/import fallback. User-facing category displays should migrate to the new resolver rather than reading `Asset.category` directly.

## Category Resolution

Every app feature should use a shared category resolver.

Resolution order:

1. Normalize the asset symbol.
2. If a `CategorySymbolRule` exists for that symbol, return its category.
3. Otherwise map the legacy/import `AssetCategory` to a matching configurable category.
4. If no matching configurable category exists, return the fallback category.

Legacy/import fallback mapping:

- `.stablecoin` -> Stablecoins
- `.defi` -> DeFi
- `.meme` -> Meme
- `.privacy` -> Privacy
- `.fiat` -> Fiat
- `.major`, `.governance`, `.other` -> Other Tokens unless a symbol rule exists

This keeps imported provider data useful while making user rules authoritative.

## App-Wide Consumers

The shared resolver should drive:

- Exposure category table and summary calculations.
- Overview category donut.
- All Assets category column, grouping, sorting, and CSV export.
- Performance category charts, category change rows, and category toggles.
- Portfolio Health stablecoin ratio and related category-derived metrics.
- Asset Detail metadata category badge.
- Debug endpoints that display categories to the user.

Stablecoin-sensitive logic should use the resolved category semantic role, not the old enum, so user changes are respected consistently.

## Settings UX

Add a category management area in Settings.

Users can:

- View all categories in order.
- Create a category.
- Rename a category.
- Reorder categories.
- Delete non-required categories.
- Add symbols to a category.
- Remove symbols from a category.
- Move a symbol between categories.

Deleting a category must reassign its symbols, defaulting to Other Tokens. The UI should prevent duplicate symbol ownership by moving an existing symbol rule to the selected category rather than creating a duplicate.

## Migration And Seeding

On first launch after the feature ships:

1. Seed default categories when no `PortfolioCategory` records exist.
2. Seed default symbol rules when no `CategorySymbolRule` records exist.
3. Leave existing `Asset.category` values untouched.

The seeding step must be idempotent. If the user later edits categories, app launches must not reset their choices.

## Architecture

Use the existing SwiftUI + TCA style.

- PortuCore owns the persisted models and pure resolver types.
- The app target owns Settings UI, seeding orchestration, and feature integration.
- Pure functions should accept lightweight category resolution snapshots instead of SwiftData models where possible, so tests remain fast and deterministic.
- Views should receive already-resolved category display data or a small resolver snapshot, not perform ad hoc symbol matching.

## Error Handling

- If category seeding fails, the app should fall back to a generated in-memory default resolver for the current run and surface a concise settings/debug error if needed.
- If a rule points to a missing category, resolution should ignore the invalid rule and use fallback mapping.
- If the fallback category is missing, the resolver should synthesize an `Other Tokens` display category rather than crashing.
- Empty or whitespace-only symbols are invalid and should not be saved as rules.

## Testing

Add Swift Testing coverage for:

- Default category seeding excludes SUI and includes BTC, ETH, SOL.
- Default symbol rules map BTC, ETH, and SOL families.
- Global symbol rules override legacy/import category.
- DeFi and Meme remain separate by default.
- Unknown `.major`, `.governance`, and `.other` assets resolve to Other Tokens.
- Stablecoin semantic role drives Portfolio Health and Exposure stablecoin exclusion.
- Category resolver is deterministic and handles missing fallback data.
- Settings reducer can create, rename, delete, reorder, and move symbols.
- App-wide pure functions use resolved categories instead of raw `AssetCategory`.
- Render smoke tests cover the Settings category management area and existing dashboard sections.

Run focused category resolver and Settings tests first, then the full Xcode scheme.

## Open Decisions

None for v1. Asset-specific overrides are explicitly deferred.
