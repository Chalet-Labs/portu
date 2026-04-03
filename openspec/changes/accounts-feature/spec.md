# AccountsFeature — TCA Migration Spec

## Scope

Migrate `AccountsView` from `@Environment(AppState.self)` + `@State` to TCA.
`AddAccountSheet` keeps its form `@State` (local, resets on dismiss).

### In scope
- Child reducer `AccountsFeature` under `AppFeature`
- Filter/search/presentation state in reducer (replacing `@State`)
- Pure functions for: account row mapping, filtering, group extraction, form validation
- Lightweight `AccountInput` struct decoupling from SwiftData models
- Views read from store, @Query stays in views

### Out of scope
- `sortOrder` (KeyPathComparator not Equatable — stays as view-local `@State`)
- AddAccountSheet form fields (19 @State properties — purely local form state)
- Save/delete side effects (SwiftData + Keychain — stay in views for now)
- Context menu actions (toggle active, delete — mutate SwiftData directly)

---

## Behaviors

### B1: Search text
- Text field updates search text through reducer action
- Used by `filterAccountRows` to filter by name

### B2: Group filter
- Picker sets group filter (nil = all groups)
- State change through reducer action

### B3: Show inactive toggle
- Toggle sets show/hide inactive accounts
- State change through reducer action

### B4: Show add sheet
- Button opens add account sheet
- Dismiss closes it
- State change through reducer action

### B5: Account row mapping
- Given a list of `AccountInput` entries:
  - Maps to `AccountRowData` with name, group, address (truncated to 16 chars + ellipsis),
    type (kind capitalized), balance, isActive, lastSyncError
  - Group defaults to em dash "—" when nil
  - Address: first wallet address, or exchange type capitalized, or "Manual"

### B6: Account row filtering
- Given rows + filter criteria:
  - Filters out inactive accounts unless `showInactive` is true
  - Filters by search text (case-insensitive name match)
  - Filters by group (nil = show all)

### B7: Group extraction
- Given a list of `AccountInput` entries:
  - Returns sorted unique non-nil group names

### B8: Form validation (canSave)
- Tab 0 (Chain): requires non-empty name AND address
- Tab 1 (Manual): requires non-empty name
- Tab 2 (Exchange): requires non-empty name AND API key AND API secret
