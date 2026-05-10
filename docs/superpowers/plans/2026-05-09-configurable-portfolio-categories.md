# Configurable Portfolio Categories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add app-wide, user-configurable portfolio categories backed by global symbol rules and shared category resolution.

**Architecture:** PortuCore owns the persisted category models and pure resolver snapshots. The app target seeds defaults, exposes category settings, and passes a resolver snapshot into existing dashboard features. Existing raw `AssetCategory` remains as legacy/import fallback while user-facing category surfaces move to resolved portfolio categories.

**Tech Stack:** Swift 6.2, SwiftData, SwiftUI, TCA, Swift Testing, XcodeGen.

---

### Task 1: Core Category Model And Resolver

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PortfolioCategory.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/CategorySymbolRule.swift`
- Create: `Packages/PortuCore/Sources/PortuCore/Models/PortfolioCategoryResolver.swift`
- Modify: `Sources/Portu/App/ModelContainerFactory.swift`
- Test: `Tests/PortuTests/PortfolioCategoryResolverTests.swift`

- [ ] Write Swift Testing coverage for default categories, no SUI default, symbol normalization, global rule precedence, fallback mapping, duplicate symbol ownership, stablecoin semantic role, and missing fallback handling.
- [ ] Run `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/PortfolioCategoryResolverTests test` and verify the new tests fail because the model and resolver do not exist.
- [ ] Add the SwiftData models, stable default category IDs, default symbol rules, resolver snapshots, and symbol normalization.
- [ ] Add `PortfolioCategory.self` and `CategorySymbolRule.self` to `ModelContainerFactory.schema`.
- [ ] Re-run the focused resolver tests and verify they pass.

### Task 2: Seeding And Settings Management

**Files:**
- Create: `Sources/Portu/App/PortfolioCategorySeeder.swift`
- Create: `Sources/Portu/Features/Settings/CategorySettingsTab.swift`
- Modify: `Sources/Portu/App/PortuApp.swift`
- Modify: `Sources/Portu/Features/Settings/SettingsView.swift`
- Modify: `Sources/Portu/Features/Settings/SettingsComponents.swift`
- Test: `Tests/PortuTests/PortfolioCategorySeederTests.swift`
- Test: `Tests/PortuTests/SettingsTabTests.swift`
- Test: `Tests/PortuTests/ViewRenderSmokeTests.swift`

- [ ] Write Swift Testing coverage proving seeding is idempotent, seeding excludes SUI, user edits are not reset, symbol rules are inserted only once, and Settings includes a Categories tab.
- [ ] Run focused seeder/settings tests and verify they fail before implementation.
- [ ] Implement `PortfolioCategorySeeder.seedIfNeeded(in:)` using fetch-all descriptors and idempotent insertion.
- [ ] Call seeding from `PortuApp.init()` after the model container is created.
- [ ] Add a Settings Categories tab that can create, rename, reorder, delete non-required categories, and add/remove/move global symbol rules.
- [ ] Add a render smoke test for the Settings Categories tab.
- [ ] Re-run focused seeder/settings/render tests and verify they pass.

### Task 3: Feature Data Flow Integration

**Files:**
- Modify: `Sources/Portu/Features/AllAssets/AllAssetsFeature.swift`
- Modify: `Sources/Portu/Features/AllAssets/AssetsTab.swift`
- Modify: `Sources/Portu/Features/AllAssets/AllAssetsView.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewFeature.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewView.swift`
- Modify: `Sources/Portu/Features/Overview/TopAssetsDonut.swift`
- Modify: `Sources/Portu/Features/Overview/PortfolioHealthFeature.swift`
- Modify: `Sources/Portu/Features/Overview/PortfolioHealthPanel.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewSummaryCards.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewPositionTabs.swift`
- Modify: `Sources/Portu/Features/Exposure/ExposureFeature.swift`
- Modify: `Sources/Portu/Features/Exposure/ExposureView.swift`
- Modify: `Sources/Portu/Features/AssetDetail/AssetMetadataSidebar.swift`
- Test: `Tests/PortuTests/AllAssetsFeatureTests.swift`
- Test: `Tests/PortuTests/OverviewFeatureTests.swift`
- Test: `Tests/PortuTests/ExposureFeatureTests.swift`
- Test: `Tests/PortuTests/PortfolioHealthFeatureTests.swift`
- Test: `Tests/PortuTests/PortfolioHealthMetricsTests.swift`

- [ ] Write or update focused tests showing All Assets, Overview, Exposure, and Portfolio Health use resolved portfolio categories instead of raw `AssetCategory`.
- [ ] Run the focused feature tests and verify they fail before integration.
- [ ] Extend `TokenEntry` and related row data with resolved portfolio category snapshots while keeping raw `AssetCategory` as legacy fallback input.
- [ ] Update views with `@Query` category/rule snapshots and pass `PortfolioCategoryResolver` into token entry builders and pure functions.
- [ ] Replace raw category display/grouping/export with resolved category names.
- [ ] Replace stablecoin-sensitive logic with resolved category semantic role.
- [ ] Re-run focused feature tests and verify they pass.

### Task 4: Performance And Debug Integration

**Files:**
- Modify: `Sources/Portu/Features/Performance/PerformanceFeature.swift`
- Modify: `Sources/Portu/Features/Performance/AssetsChartMode.swift`
- Modify: `Sources/Portu/Features/Performance/PerformanceBottomPanel.swift`
- Modify: `Sources/Portu/Debug/DebugEndpoints.swift`
- Test: `Tests/PortuTests/PerformanceFeatureTests.swift`
- Test: `Tests/PortuTests/DebugEndpointsTests.swift`

- [ ] Write or update tests proving category chart points, category toggles, category changes, and debug category output use resolved categories.
- [ ] Run focused performance/debug tests and verify they fail before integration.
- [ ] Update `CategorySnapshotEntry` and performance state to use resolved category IDs/names instead of raw enum values.
- [ ] Update chart toggles to render the resolved category list.
- [ ] Update debug endpoints that display category strings to use resolved categories where a symbol and legacy category are available.
- [ ] Re-run focused performance/debug tests and verify they pass.

### Task 5: Full Verification

**Files:**
- Verify all modified files.

- [ ] Run `just generate` if project generation is stale.
- [ ] Run focused category, settings, feature, performance, and debug tests.
- [ ] Run `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation test`.
- [ ] Run `./script/build_and_run.sh --verify`.
- [ ] Open the app, inspect Settings > Categories and the Exposure category table.
- [ ] Confirm `git status --short --branch` contains only expected implementation changes.
