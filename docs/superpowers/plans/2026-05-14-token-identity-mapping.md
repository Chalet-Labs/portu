# Token Identity Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Portu price Zapper-originated onchain assets through a `(chain, address)` identity cache, using CoinGecko IDs when available and Zapper current/historical prices otherwise.

**Architecture:** Add a `TokenIdentityMapping` SwiftData model keyed by `(chain, contractAddress)` via a unique canonical key. Keep automatic provider mappings separate from `TokenPricingOverride`; views and backfill use mapping snapshots to resolve effective price keys. Price polling accepts the existing string IDs, with `zapper:<chain>:<address>` keys routed to Zapper current-price batch lookup.

**Tech Stack:** Swift 6.2, SwiftData, Swift Testing, TCA, CoinGecko REST API, Zapper GraphQL.

---

### Task 1: Core Identity Model

**Files:**
- Create: `Packages/PortuCore/Sources/PortuCore/Models/TokenIdentityMapping.swift`
- Modify: `Packages/PortuCore/Sources/PortuCore/DTOs/OnchainTokenIdentity.swift`
- Modify: `Sources/Portu/App/ModelContainerFactory.swift`
- Modify test schemas that list SwiftData models.
- Test: `Packages/PortuCore/Tests/PortuCoreTests/ModelTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests proving `OnchainTokenIdentity` parses `zapper:<chain>:<address>` IDs and `TokenIdentityMapping` stores a unique canonical key without changing user overrides.

- [ ] **Step 2: Run focused Core tests**

Run: `swift test --package-path Packages/PortuCore --filter ModelTests`
Expected: FAIL because `TokenIdentityMapping` does not exist.

- [ ] **Step 3: Implement model and parser**

Add a SwiftData `@Model` with unique `canonicalKey`, provider ID fields, timestamps, and normalization helpers. Add `OnchainTokenIdentity.init?(historicalPriceID:)`.

- [ ] **Step 4: Run focused Core tests**

Run: `swift test --package-path Packages/PortuCore --filter ModelTests`
Expected: PASS.

### Task 2: Zapper Current Price Batch

**Files:**
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ZapperGraphQLTypes.swift`
- Modify: `Packages/PortuNetwork/Sources/PortuNetwork/Providers/ZapperProvider.swift`
- Test: `Packages/PortuNetwork/Tests/PortuNetworkTests/ZapperProviderTests.swift`

- [ ] **Step 1: Write failing tests**

Add a test for `fetchPriceUpdate(for:)` that asserts the GraphQL query uses `fungibleTokenBatchV2`, sends address and chain ID pairs, and returns prices plus 24h changes keyed by `identity.historicalPriceID`.

- [ ] **Step 2: Run focused Zapper tests**

Run: `swift test --package-path Packages/PortuNetwork --filter ZapperProviderTests`
Expected: FAIL because the current-price method does not exist.

- [ ] **Step 3: Implement batch current-price fetch**

Add query, variables, response DTOs, and `ZapperProvider.fetchPriceUpdate(for:)`. Convert Zapper 24h percentage values to the same decimal ratio shape used by `PriceUpdate`.

- [ ] **Step 4: Run focused Zapper tests**

Run: `swift test --package-path Packages/PortuNetwork --filter ZapperProviderTests`
Expected: PASS.

### Task 3: Price Key Resolution In App

**Files:**
- Create: `Sources/Portu/Features/Shared/TokenIdentityMappingFeature.swift`
- Modify: `Sources/Portu/Features/Settings/TokenSettingsFeature.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewPricePolling.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewFeature.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewView.swift`
- Modify: `Sources/Portu/Features/Exposure/ExposureView.swift`
- Modify: `Sources/Portu/Features/Overview/PriceWatchlist.swift`
- Modify: `Sources/Portu/Features/Overview/OverviewTopBar.swift`
- Test: `Tests/PortuTests/OverviewFeatureTests.swift`
- Test: `Tests/PortuTests/TokenSettingsFeatureTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests showing dashboard price polling includes `zapper:<chain>:<address>` for eligible unmapped onchain tokens, uses cached mapping CoinGecko IDs before Zapper keys, and resolves live Zapper prices in token settings and overview rows.

- [ ] **Step 2: Run focused app tests**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/OverviewFeatureTests -only-testing:PortuTests/TokenSettingsFeatureTests test`
Expected: FAIL because mapping snapshots and Zapper price keys are not wired.

- [ ] **Step 3: Implement app-level mapping snapshots and effective price keys**

Add `TokenIdentityMappingSnapshot`, mapping lookup helpers, and effective price-key helpers. Update Overview, Exposure, PriceWatchlist, and top-bar calculations to use mapped tokens and Zapper fallback keys without changing manual override precedence.

- [ ] **Step 4: Run focused app tests**

Run the same focused `xcodebuild` command.
Expected: PASS.

### Task 4: Polling Pipeline

**Files:**
- Create: `Sources/Portu/App/PricePollingIDResolver.swift`
- Modify: `Sources/Portu/App/AppFeature.swift`
- Modify: `Sources/Portu/App/PortuApp.swift`
- Test: `Tests/PortuTests/AppFeatureTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests showing mixed CoinGecko IDs and `zapper:` IDs are partitioned, CoinGecko and Zapper updates are merged, and missing Zapper API key leaves CoinGecko polling unaffected.

- [ ] **Step 2: Run focused app feature tests**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/AppFeatureTests test`
Expected: FAIL because Zapper price IDs are still sent to CoinGecko.

- [ ] **Step 3: Implement polling split and merge**

Route normal IDs to CoinGecko and `zapper:<chain>:<address>` IDs to `ZapperProvider.fetchPriceUpdate(for:)`. Preserve existing `AppFeature.startPricePolling([String])` so view task wiring stays small.

- [ ] **Step 4: Run focused app feature tests**

Run the same focused `xcodebuild` command.
Expected: PASS.

### Task 5: Backfill Mapping Cache

**Files:**
- Modify: `Sources/Portu/Features/Settings/HistoricalPriceBackfillClient.swift`
- Modify: `Sources/Portu/Features/Settings/HistoricalPriceBackfillFeature.swift`
- Test: `Tests/PortuTests/HistoricalPriceBackfillFeatureTests.swift`
- Test: `Tests/PortuTests/HistoricalPriceBackfillLiveTests.swift`

- [ ] **Step 1: Write failing tests**

Update backfill tests so automatic CoinGecko resolution persists `TokenIdentityMapping` rows, not `TokenPricingOverride`, and cached mappings are reused without another resolver call.

- [ ] **Step 2: Run focused backfill tests**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation -only-testing:PortuTests/HistoricalPriceBackfillFeatureTests -only-testing:PortuTests/HistoricalPriceBackfillLiveTests test`
Expected: FAIL because backfill still writes automatic mappings into `TokenPricingOverride`.

- [ ] **Step 3: Implement mapping-aware backfill**

Fetch mappings, pass mapping snapshots into candidate resolution, persist newly resolved CoinGecko IDs to `TokenIdentityMapping`, and leave `TokenPricingOverride` untouched except for user actions.

- [ ] **Step 4: Run focused backfill tests**

Run the same focused backfill command.
Expected: PASS.

### Task 6: Full Verification

**Files:**
- All files touched above.

- [ ] **Step 1: Run package tests**

Run: `just test-packages`
Expected: PASS.

- [ ] **Step 2: Run full Xcode tests**

Run: `xcodebuild -project Portu.xcodeproj -scheme Portu -configuration Debug -derivedDataPath .build/DerivedData -skipMacroValidation test`
Expected: PASS.

- [ ] **Step 3: Launch and smoke-test app**

Run: `./script/build_and_run.sh --verify`
Expected: app builds and Portu process is running. If `xcodegen` is unavailable in the script environment, run the equivalent `xcodebuild` command and launch the Debug app directly.
