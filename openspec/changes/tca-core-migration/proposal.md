# TCA Core Migration

## What
Migrate the root app coordination layer from `@Observable AppState` + imperative `SyncEngine` to a TCA `AppFeature` reducer with explicit state, actions, and effects.

## Why
- Testable: TestStore provides exhaustive assertion on every state change
- Predictable: All state mutations go through reducer, no hidden mutation paths
- Composable: Child features can be scoped from root reducer in Phase 4

## Scope
- AppState → AppFeature.State
- SyncEngine → TCA Effect (via SyncEngineClient dependency)
- PriceService → TCA Effect (via PriceServiceClient dependency)
- SecretStore → TCA dependency (KeychainClient)
- PortuApp entry point → Store<AppFeature>
- SwiftData @Query stays in views (not migrated to TCA)
