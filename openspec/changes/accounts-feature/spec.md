# AccountsFeature — TCA Migration Spec

## Scope

Migrate `AccountsView` from `@Environment(AppState.self)` + `@State` to TCA.
`AddAccountSheet` uses local draft state for add/edit form fields.

### In scope
- Child reducer `AccountsFeature` under `AppFeature`
- Filter/search/account sheet presentation state in reducer (replacing `@State`)
- Pure functions for: account row mapping, filtering, group extraction, form validation
- Lightweight `AccountInput` struct decoupling from SwiftData models
- Views read from store, @Query stays in views
- Account-scoped sync entry point exposed through `AppFeature`

### Out of scope
- `sortOrder` (KeyPathComparator not Equatable — stays as view-local `@State`)
- Reducer-owned SwiftData mutations for account row actions; views route toggle/delete
  through `AccountSheetSaveCoordinator` for save, rollback, and credential cleanup
- Reducer-owned context menu effects; context menu actions remain view-driven and
  delegate account persistence to `AccountSheetSaveCoordinator`

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

### B4: Show account sheet
- Add button opens add account sheet mode
- Edit row/context action opens edit account sheet mode for the selected account id
- Dismiss clears the sheet mode through reducer action

### B5: Account row mapping
- Given a list of `AccountInput` entries:
  - Maps to `AccountRowData` with name, group, full address, type (kind capitalized),
    balance, dataSource, isActive, lastSyncError
  - Group defaults to em dash "—" when nil
  - Address: wallet first address or em dash when missing; exchange type capitalized
    or "Exchange" when missing; "Manual" for manual accounts
  - Row is syncable only when active and not manual

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

### B9: Edit account sheet
- Edit mode pre-fills current account data
- Edit mode locks the account type instead of allowing tab switching
- Wallet edit updates name, group, notes, first address, and chain/EVM selection
- Manual edit updates name, group, and notes
- Exchange edit pre-fills and saves credentials for the same account id

### B10: Account-scoped sync
- Account row Sync and edit sheet Sync call the app-level account sync action
- Sync is disabled for manual accounts, inactive accounts, and while another sync is running
- Account-scoped sync updates the same global `SyncStatus` as full/provider sync
