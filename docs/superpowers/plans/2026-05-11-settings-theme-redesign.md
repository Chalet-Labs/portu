# Settings Theme Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle Portu Settings to match the dark dashboard theme while preserving current Settings behavior and tab boundaries.

**Architecture:** Keep the existing Settings route and tab structure. Replace the light-only settings palette and compact component styling with dashboard-compatible colors and controls, then remove the forced light color scheme from the Settings route. Tests define the dark theme contract and guard the real category defaults.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, SwiftData, TCA, XcodeGen/xcodebuild.

---

## File Structure

- Modify `Tests/PortuTests/SettingsTabTests.swift`: add focused tests for the dashboard theme contract and category default labels.
- Modify `Sources/Portu/Features/Settings/SettingsComponents.swift`: update shared Settings surfaces, controls, badges, notices, buttons, and color constants to use dashboard-compatible styling.
- Modify `Sources/Portu/Features/Settings/SettingsView.swift`: update sidebar icons/selection, metrics, General tab segmented control, and remove light-specific control colors.
- Modify `Sources/Portu/App/ContentView.swift`: stop forcing the Settings route into light mode.
- Optionally modify settings tab files only where existing text-button controls need icon-first styling or dark-theme contrast fixes.

## Task 1: Theme Contract Tests

**Files:**

- Modify: `Tests/PortuTests/SettingsTabTests.swift`
- Later modify: `Sources/Portu/Features/Settings/SettingsComponents.swift`
- Later modify: `Sources/Portu/App/ContentView.swift`

- [ ] **Step 1: Write the failing test**

Add tests that assert Settings exposes a dashboard dark-theme contract, uses a dashboard-compatible panel radius, does not force a light color scheme, and still uses the real configurable portfolio category names instead of a user-facing Major category.

- [ ] **Step 2: Run the focused Settings test to verify RED**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/SettingsTabTests test`

Expected: FAIL because the new dark-theme contract API does not exist yet.

- [ ] **Step 3: Implement the minimal theme contract**

Add the small production surface needed by the failing tests: dark theme flags or color-scheme metadata, compact dashboard radii, and category-name expectations sourced from existing defaults. Do not restyle every screen yet.

- [ ] **Step 4: Run the focused Settings test to verify GREEN**

Run the same focused command.

Expected: PASS.

## Task 2: Shared Settings Dark Components

**Files:**

- Modify: `Sources/Portu/Features/Settings/SettingsComponents.swift`
- Modify: `Sources/Portu/Features/Settings/SettingsView.swift`
- Test: `Tests/PortuTests/SettingsTabTests.swift`
- Test: `Tests/PortuTests/ViewRenderSmokeTests.swift`

- [ ] **Step 1: Write or extend a failing test**

Extend the Settings tests so shared Settings design constants are tied to `PortuTheme` dashboard surfaces and compact radii.

- [ ] **Step 2: Run the focused test to verify RED**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/SettingsTabTests test`

Expected: FAIL because Settings still uses the light palette.

- [ ] **Step 3: Restyle shared Settings components**

Update shared Settings components and modifiers to use dark dashboard surfaces, gold accents, compact radii, dark input/menu frames, dark notices, dark badges, and disabled states with adequate contrast.

- [ ] **Step 4: Run focused tests**

Run the Settings test command again.

Expected: PASS.

## Task 3: Settings Route And Tab Screen Polish

**Files:**

- Modify: `Sources/Portu/App/ContentView.swift`
- Modify: `Sources/Portu/Features/Settings/SettingsView.swift`
- Modify as needed: `Sources/Portu/Features/Settings/CategorySettingsTab.swift`
- Modify as needed: `Sources/Portu/Features/Settings/APIKeysSettingsTab.swift`
- Modify as needed: `Sources/Portu/Features/Settings/DebugSettingsTab.swift`
- Test: `Tests/PortuTests/ViewRenderSmokeTests.swift`

- [ ] **Step 1: Write or extend a failing render/contract test**

Add a focused render or contract assertion that Settings is presented as a dark dashboard route and still renders at the current supported size.

- [ ] **Step 2: Run the focused render test to verify RED**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/ViewRenderSmokeTests/settings_route_renders_without_crashing test`

If Xcode cannot resolve the exact Swift Testing method selector, run the full `ViewRenderSmokeTests` suite instead.

Expected: FAIL only if the new test defines missing behavior; existing render smoke tests may already pass before visual restyling.

- [ ] **Step 3: Apply route and screen polish**

Remove the forced light scheme from the Settings route. Adjust sidebar rows, selected states, General segmented control, category editor rows, API key rows, RPC table, and Debug code/notices only as needed for dark-theme readability and the approved mock direction.

- [ ] **Step 4: Run focused render tests**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/ViewRenderSmokeTests test`

Expected: PASS.

## Task 4: Full Verification

**Files:**

- No new source files expected.

- [ ] **Step 1: Run focused Settings behavior tests**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/SettingsTabTests test`

Expected: PASS.

- [ ] **Step 2: Run package tests**

Run: `just test-packages`

Expected: PASS.

- [ ] **Step 3: Run full Xcode scheme tests**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation test`

Expected: PASS.

- [ ] **Step 4: Build and launch verification**

Run: `./script/build_and_run.sh --verify`

Expected: build succeeds and the `Portu` process is confirmed running.

## Plan Self-Review

- Spec coverage: The plan covers the dark dashboard theme, separate screens per tab, correct category labels, no light route, accessibility-preserving controls, and existing behavior preservation.
- Placeholder scan: No placeholder steps remain; each step has a file scope, command, and expected result.
- Type consistency: The plan references existing files and types only, except for the new small theme contract added under Task 1 by TDD.
