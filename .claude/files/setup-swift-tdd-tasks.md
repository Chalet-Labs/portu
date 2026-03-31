# Portu — TCA + TDD Retrofit Task List

*Created 2026-03-29. Reference: research-swift-tdd-ai-solopreneur.md*

## Phase 1: Tooling Setup ✅

- [x] 1.1 Install XcodeBuildMCP v2.3.1 (brew)
- [x] 1.2 `.mcp.json` created via `claude mcp add -s project` (Sentry telemetry disabled)
- [x] 1.3 OpenSpec v1.2.0 installed + `openspec init` (4 skills, 4 commands)
- [x] ~~1.4~~ Dropped — `swift-testing-pro` skill covers steipete's playbook and more
- [x] ~~1.5~~ Dropped — `swiftui-pro` + other agent skills already installed
- [x] 1.6 CLAUDE.md updated with TDD rules (full RED→GREEN→REFACTOR cycle)
- [x] 1.7 XcodeBuildMCP verified: discovers project, lists schemes, runs tests
  - Note: 3 app-level tests crash (pre-existing SwiftData/MainActor issue)
  - Package tests pass (`just test-packages`)
  - Also fixed: `project.yml` missing `GENERATE_INFOPLIST_FILE: YES` for PortuTests
  - Also fixed: stale `.crypto` → `.major` in SyncEngineTests

## Phase 2: Add Dependencies ✅

- [x] 2.1 TCA 1.25.3 added to `project.yml` (app target dependency)
- [x] 2.2 swift-snapshot-testing 1.19.1 added (PortuTests dependency)
- [x] ~~2.3~~ Prefire removed — UIKit-only, not macOS compatible
- [x] ~~2.4~~ Dropped — OpenSpec manages specs in `openspec/changes/`
- [x] ~~2.5~~ Dropped — no XCUITest planned; accessibility IDs added when needed
- [x] 2.6 Build verified: `just generate && just build` succeeds
  - Also fixed: added `-skipMacroValidation` to justfile for TCA/CasePaths/Dependencies macros

## Phase 3: TCA Migration — Core Layer ✅

- [x] 3.1 Behavioral spec written (`openspec/changes/tca-core-migration/spec.md`)
- [x] 3.2 AppFeature reducer with @ObservableState, 8 TestStore tests (all pass)
- [x] 3.3 SyncEngine refactored: returns `SyncResult`, no AppState dependency
- [x] 3.4 SyncEngineClient + PriceServiceClient with live/test implementations
- [x] 3.5 PortuApp creates Store with live deps, bridge to AppState via `onSyncRequested`
- [x] 3.6 10 tests pass (8 AppFeature + 1 PortuApp + 1 PortuUI); SyncEngineTests crash (pre-existing)
  - Removed `defaultIsolation(MainActor.self)` from app target — incompatible with TCA
  - Removed Prefire — UIKit-only
  - Added `Equatable` to PortuCore.PriceUpdate and SyncError
  - Reused PortuCore.PriceUpdate instead of duplicating in AppFeature

## Phase 4: TCA Migration — Features

Migrate each feature module to TCA reducers.

- [x] 4.1 AllAssetsFeature (list view + filtering)
  - AllAssetsFeature @Reducer with State (selectedTab, searchText, grouping), Action, child of AppFeature
  - Extracted row aggregation as testable pure functions (aggregateRows, filterRows, generateCSV)
  - TokenEntry struct decouples aggregation from SwiftData models
  - 13 tests: 3 reducer (TestStore) + 7 aggregation + 3 filtering/CSV
  - Views updated: store bindings instead of @State, prices from parent store instead of AppState
- [x] 4.2 AssetDetailFeature (price chart + positions)
  - AssetDetailFeature @Reducer with State (chartMode, selectedRange), Action (chartModeChanged, timeRangeChanged), child of AppFeature
  - Extracted pure functions: aggregatePositionRows, computeHoldingsSummary, aggregateSnapshots, headerPriceInfo
  - Input structs: PositionTokenEntry (per-token with account/position context), SnapshotEntry (decouples from @Model)
  - Output structs: PositionRowData, HoldingsSummary + ChainBreakdown, ChartDataPoint, AssetPriceInfo
  - 21 tests: 2 reducer (TestStore) + 6 position row + 6 holdings summary + 3 snapshot aggregation + 4 header price
  - Views updated: store bindings instead of @State, prices from parent store instead of AppState
  - AssetMetadataSidebar unchanged (already pure — no AppState dependency)
- [x] 4.3 AccountsFeature (sortable table + add account)
  - AccountsFeature @Reducer with State (searchText, filterGroup, showInactive, showAddSheet), child of AppFeature
  - Extracted pure functions: mapAccountRows, filterAccountRows, extractGroups, canSave
  - AccountInput struct decouples from SwiftData models
  - AccountRowData nonisolated struct for table display
  - 21 tests: 4 reducer (TestStore) + 5 row mapping + 6 filtering + 2 group extraction + 4 form validation
  - Views updated: store bindings instead of @State, pure functions instead of inline logic
  - AddAccountSheet uses canSave from feature; form @State stays local (resets on dismiss)
- [x] 4.4 ExposureFeature (exposure breakdown)
  - ExposureFeature @Reducer with State (showByAsset), child of AppFeature
  - Extracted pure functions: computeCategoryExposure, computeAssetExposure, computeSummary, resolveTokenUSDValue
  - Reuses TokenEntry from AllAssetsFeature (same input shape)
  - Output structs: CategoryExposure, AssetExposure, ExposureSummary
  - 15 tests: 1 reducer + 5 category + 3 asset + 3 summary + 3 token value
  - Views updated: store bindings, pure functions, tokenEntries mapping from @Query
- [x] 4.5 PerformanceFeature (analytics)
  - PerformanceFeature @Reducer with State (selectedAccountId, selectedRange, chartMode, disabledCategories, showCumulative)
  - Extracted pure functions: lastPerDay, computePnLBars, computeCategoryChanges
  - New enums: PerformanceChartMode (value/assets/pnl), PerformanceTimeRange (1W-Custom)
  - Output structs: PnLBar, CategoryChange, CategorySnapshotEntry
  - 14 tests: 5 reducer + 3 lastPerDay + 3 PnL + 3 category change
  - All child chart views (ValueChartMode, AssetsChartMode, PnLChartMode) migrated
  - PerformanceBottomPanel uses computeCategoryChanges pure function
- [x] 4.6 StatusBarFeature (menu bar)
  - No child reducer needed — reads directly from AppFeature.State
  - Replaced @Environment(AppState.self) with store: StoreOf<AppFeature>
  - Reads syncStatus, storeIsEphemeral, lastPriceUpdate from store
- [x] 4.7 Each feature has TestStore tests before migration is "done"
  - 96 tests across 24 suites — all features have full TestStore + pure function coverage

## Phase 5: CI/CD

- [x] 5.1 GitHub Actions workflow (`.github/workflows/ci.yml`)
  - `macos-15` runner, Xcode latest-stable, XcodeGen + just via brew
  - Triggers on push/PR to master, 30-min timeout, concurrency cancellation
  - Steps: generate → build → test-packages → test
- [x] ~~5.2~~ Dropped — no Apple Developer license; personal app, no signing/notarization needed
- [x] 5.3 Verify: full build + test suite passes on CI
  - PR #4 — all steps green in 4m23s
  - Node.js 20 deprecation warning on actions (cosmetic, deadline Sep 2026)
- [x] ~~5.4~~ Dropped — no Developer ID cert; `just release` builds locally without signing

## Phase 6: Validate SDD Pipeline

- [ ] 6.1 Write behavioral spec for a NEW feature with OpenSpec
- [ ] 6.2 Generate tests from spec → verify RED
- [ ] 6.3 AI implements freely → verify GREEN
- [ ] 6.4 Add #Preview + verify Prefire snapshot generation
- [ ] 6.5 Full suite passes locally + on CI
- [ ] 6.6 Retrospective: what worked, what to adjust

---

## Decisions Made
- Architecture: TCA (full migration from @Observable)
- Target: macOS 15+
- Distribution: Personal use (no Apple Developer license)
- Testing: Swift Testing (XCTest only for XCUITest)
- Spec tooling: OpenSpec
- CI: GitHub Actions
- Release: Local `just release` (no signing)
- AI: Claude Code + XcodeBuildMCP
- Project gen: XcodeGen (existing `project.yml`)

## Current State
- @Observable AppState, SyncEngine, 3 SPM packages, Swift Testing tests
- CLAUDE.md with TDD rules, .mcp.json with XcodeBuildMCP, OpenSpec initialized
- TCA + swift-snapshot-testing + Prefire added as dependencies (builds clean)
- 3 app-level tests crash (pre-existing SwiftData/MainActor issue, fix in Phase 3)
- No CI yet, no TCA usage yet
