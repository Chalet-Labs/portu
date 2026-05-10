# Token Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add performance-safe token visibility and pricing overrides with a searchable Token Settings screen capped at 100 rows.

**Architecture:** Add a user-owned `TokenPricingOverride` SwiftData model in `PortuCore`, then add app-level pure functions that combine `TokenEntry`, live prices, overrides, and dashboard settings. Heavy dashboard views use filtered dashboard-eligible entries for aggregation, while the Settings `Tokens` tab uses capped row shaping and writes overrides.

**Tech Stack:** Swift 6.2, SwiftData, SwiftUI, TCA, Swift Testing, Xcode scheme tests.

---

### Task 1: Override Model and Schema

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/TokenPricingOverride.swift`
- Modify: `Sources/Portu/App/ModelContainerFactory.swift`
- Modify: `Tests/PortuTests/ViewRenderSmokeTests.swift`
- Test: `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`

- [ ] Write a failing Swift Testing test that creates a `TokenPricingOverride`, stores manual price, CoinGecko override, ignore, and always-show fields.
- [ ] Run `swift test --package-path Packages/PortuCore --filter "token pricing override stores user pricing and visibility settings"` and verify it fails because the model does not exist.
- [ ] Add the model with `id`, `assetId`, `manualPriceUSD`, `coinGeckoIdOverride`, `isIgnored`, `alwaysShow`, `notes`, `createdAt`, and `updatedAt`.
- [ ] Add `TokenPricingOverride.self` to app/test SwiftData schemas.
- [ ] Re-run the focused PortuCore test.

### Task 2: Dashboard Eligibility and Token Settings Row Shaping

**Files:**
- Create: `Sources/Portu/Features/Settings/TokenSettingsFeature.swift`
- Test: `Tests/PortuTests/TokenSettingsFeatureTests.swift`

- [ ] Write failing tests for default `$1.00` dashboard threshold, zero amount exclusion, ignored exclusion, unpriced exclusion, dust exclusion, `alwaysShow`, manual price eligibility, row filtering, capped 100-row display, and counts.
- [ ] Run `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/TokenSettingsFeatureTests test` and verify the tests fail because the feature types do not exist.
- [ ] Implement `TokenDashboardSettings`, `TokenPricingOverrideSnapshot`, `TokenPricingSource`, `TokenVisibilityStatus`, `TokenSettingsFilter`, `TokenSettingsRow`, `TokenSettingsCounts`, and `TokenSettingsFeature`.
- [ ] Re-run focused tests until green.

### Task 3: Settings UI

**Files:**
- Create: `Sources/Portu/Features/Settings/TokenSettingsTab.swift`
- Modify: `Sources/Portu/Features/Settings/SettingsView.swift`
- Test: `Tests/PortuTests/SettingsTabTests.swift`
- Test: `Tests/PortuTests/ViewRenderSmokeTests.swift`

- [ ] Write failing tests that `SettingsTab.visibleTabs(debugEnabled:)` includes `.tokens`, settings search finds `Tokens`, and `TokenSettingsTab` renders.
- [ ] Run focused settings/view tests and verify failure.
- [ ] Add the `Tokens` settings tab, global threshold controls, capped searchable table, filters, and per-row override controls.
- [ ] Re-run focused tests until green.

### Task 4: Heavy View Filtering

**Files:**
- Modify: `Sources/Portu/Features/Exposure/ExposureView.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewView.swift`
- Modify: `Sources/Portu/Features/Overview/TopAssetsDonut.swift`
- Modify: `Sources/Portu/Features/Overview/PortfolioHealthPanel.swift`
- Modify: `Sources/Portu/Features/AllAssets/AssetsTab.swift`
- Test: `Tests/PortuTests/ExposureFeatureTests.swift`
- Test: `Tests/PortuTests/OverviewFeatureTests.swift`

- [ ] Write failing tests proving Exposure aggregation excludes unpriced/dust/ignored tokens and includes manual-priced/always-show tokens.
- [ ] Run focused feature tests and verify failure.
- [ ] Wire views to query `TokenPricingOverride`, apply CoinGecko ID overrides for price polling, and aggregate dashboard-eligible token entries.
- [ ] Re-run focused feature tests until green.

### Task 5: Verification

**Files:**
- No new files.

- [ ] Run `swift test --package-path Packages/PortuCore`.
- [ ] Run `swift test --package-path Packages/PortuNetwork --filter ZapperProviderTests`.
- [ ] Run full scheme: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation test`.
- [ ] Run `./script/build_and_run.sh --verify`.
