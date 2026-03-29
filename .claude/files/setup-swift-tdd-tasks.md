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

- [ ] 4.1 AllAssetsFeature (list view + filtering)
- [ ] 4.2 AssetDetailFeature (price chart + positions)
- [ ] 4.3 AccountsFeature (sortable table + add account)
- [ ] 4.4 ExposureFeature (exposure breakdown)
- [ ] 4.5 PerformanceFeature (analytics)
- [ ] 4.6 StatusBarFeature (menu bar)
- [ ] 4.7 Each feature has TestStore tests before migration is "done"

## Phase 5: CI/CD

- [ ] 5.1 Set up GitHub Actions workflow (`.github/workflows/test.yml`)
- [ ] 5.2 Set up local Fastlane (Developer ID signing + notarization)
- [ ] 5.3 Verify: full build + test suite passes on CI
- [ ] 5.4 First Fastlane release build (sign + notarize + DMG)

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
- Distribution: Direct download (no App Store)
- Testing: Swift Testing (XCTest only for XCUITest)
- Spec tooling: OpenSpec
- CI: GitHub Actions
- Release: Local Fastlane (Developer ID + notarization)
- AI: Claude Code + XcodeBuildMCP
- Project gen: XcodeGen (existing `project.yml`)

## Current State
- @Observable AppState, SyncEngine, 3 SPM packages, Swift Testing tests
- CLAUDE.md with TDD rules, .mcp.json with XcodeBuildMCP, OpenSpec initialized
- TCA + swift-snapshot-testing + Prefire added as dependencies (builds clean)
- 3 app-level tests crash (pre-existing SwiftData/MainActor issue, fix in Phase 3)
- No CI yet, no TCA usage yet
