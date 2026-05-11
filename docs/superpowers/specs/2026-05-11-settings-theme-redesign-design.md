# Settings Theme Redesign Design

## Summary

Portu settings should visually join the rest of the dark dashboard instead of keeping a separate light settings surface. The redesign keeps the existing settings information architecture and behavior, but updates the presentation to match the current app theme: charcoal backgrounds, warm dark panels, muted beige text, bronze/gold selection states, compact controls, and dense desktop-friendly layouts.

The accepted mock direction uses five separate settings screens: General, Tokens, Categories, API Keys, and Debug. Each screen owns only its own content. API Keys and Categories are not combined.

## Goals

- Make Settings feel native to the redesigned Portu dashboard.
- Reuse the existing `PortuTheme` and shared dashboard styling where practical.
- Preserve the current Settings tab model, storage behavior, and feature boundaries.
- Keep each settings tab focused and independently scannable.
- Make Categories reflect the actual configurable portfolio category model.
- Keep controls compact, readable, and suitable for a macOS productivity app.

## Non-Goals

- Do not change settings behavior, persistence keys, or sync semantics.
- Do not add new settings tabs.
- Do not add backend sync, telemetry, or account-based preferences.
- Do not redesign the main sidebar navigation outside the Settings route.
- Do not replace the category resolver or introduce new category defaults.
- Do not convert Settings into a separate macOS Settings scene in this pass.

## Visual Direction

Settings should use the same visual language as Overview, Exposure, Accounts, and the app sidebar.

- Root background: dark charcoal dashboard background.
- Sidebar: warm dark-brown surface matching the main app sidebar.
- Panels: elevated dark panels with subtle one-pixel strokes.
- Accent: bronze/gold for selected sidebar rows, primary actions, focused segmented controls, and important status.
- Text: muted beige primary text with softer secondary and tertiary text.
- Radius: compact dashboard radius, around eight points for panels and controls.
- Density: desktop dashboard density, with short headers, compact rows, and stable table-like alignment.
- Decoration: no gradients, decorative blobs, marketing hero treatment, or oversized empty surfaces.

## Screens

### General

The General screen keeps the current price update preference. It should show:

- A compact page header with the General title and subtitle.
- A Price Updates panel.
- A refresh interval segmented control for 15 seconds, 30 seconds, 1 minute, and 5 minutes.
- A small local-only or auto-save status panel explaining that the setting is stored locally.

### Tokens

The Tokens screen keeps the existing dashboard visibility and token override workflows. It should show:

- A Dashboard Visibility panel with the minimum value input and visibility toggles.
- A Token Overrides panel with search, filter picker, compact count chips, and token rows.
- Rows for token settings should stay dense and action-oriented: symbol, name, value, pricing source, category, visibility controls, and reset action.
- Status colors should remain semantic: gold for active settings, green/teal for live or successful states, and orange/red for warning states.

### Categories

The Categories screen must use the actual configurable portfolio categories from `PortfolioCategoryDefaults`.

Default visible categories:

- BTC
- ETH
- SOL
- DeFi
- Meme
- Privacy
- Fiat
- Stablecoins
- Other Tokens

The screen must not show a user-facing `Major` category. `major` remains only a legacy `AssetCategory` fallback in the data model.

Default symbol chips should reflect the seeded rules:

- BTC: BTC, WBTC, TBTC, CBBTC
- ETH: ETH, WETH, STETH, WSTETH, RETH, CBETH, OSETH, SFRXETH
- SOL: SOL, WSOL, MSOL, JITOSOL, JUPSOL
- Stablecoins: USDC, USDC.E, USDT, DAI, USDS, FRAX, LUSD, PYUSD, GHO, FDUSD, TUSD, BUSD, USDD, USDE, CRVUSD, SUSD

The UI should preserve the current category management actions:

- Rename category.
- Reorder category.
- Delete non-required category.
- Add symbol.
- Remove symbol.
- Create category.

### API Keys

The API Keys screen should only show credential and RPC configuration content.

- Provider API Keys panel with Zapper, DeBank, and CoinGecko secure input rows.
- Each secure row should include an explicit visibility button.
- Custom RPCs panel with a compact table and add-endpoint controls.
- No category rule content should appear on this screen.

### Debug

The Debug screen remains DEBUG-only.

- Debug Server panel with enable switch, port field, and status row.
- Conditional Notices panel for restart, launch argument, and startup failure messages.
- Launch Argument panel with a compact monospaced code surface.

## Components

The redesign should consolidate Settings styling around dashboard-compatible components rather than continuing the light-only `SettingsDesign` palette.

Suggested component responsibilities:

- Settings root layout: owns the settings sidebar, detail separator, selected tab, and search filtering.
- Settings sidebar row: uses SF Symbol-style icons or compact glyph tiles, gold selected state, and dashboard row density.
- Settings page: provides title, subtitle, optional badge, scroll behavior, and content padding.
- Settings panel: replaces the current white section card with a dark dashboard card.
- Settings controls: shared input frame, menu frame, icon button, primary button, divider, badge, inline notice, and count chip styles.

Keep component APIs close to the existing `SettingsPage`, `SettingsSectionCard`, and settings control modifiers so the implementation remains scoped.

## Data Flow

No new data flow is required. Existing `@AppStorage`, SwiftData queries, `AppState`, and Keychain-backed view model behavior should remain intact.

The settings route should continue to be selected through the main app sidebar and rendered inside `ContentView`. The route should no longer force the light color scheme.

## Error Handling

Existing save and validation errors should keep their current behavior. The redesign should only restyle the surfaces:

- Token override save errors still use an alert.
- Category save errors still use an alert.
- Keychain and debug notices still use inline notice surfaces.
- Disabled buttons should remain visibly disabled and should not look like active primary actions.

## Accessibility

- Secure API key visibility buttons need clear accessibility labels.
- Icon-only buttons should continue to expose descriptive labels.
- Selected settings tab must have a visible non-color cue through shape, border, or font weight.
- Text should fit at the minimum settings width without overlapping controls.
- Controls should keep native keyboard and pointer behavior.

## Testing

Follow the repo TDD rules for implementation.

Focused tests should cover:

- Settings metrics remain compact for dashboard presentation.
- The settings route no longer forces a light-only presentation.
- Settings tab order and search behavior are unchanged.
- Category settings render with the real default category names, including BTC, ETH, and SOL, and not a Major category.
- API key inputs still default to secure mode and only reveal through explicit action.
- Existing category, token, API key, and debug settings behavior tests continue to pass.

Run focused Settings tests first, then the full Xcode scheme before calling implementation complete.
