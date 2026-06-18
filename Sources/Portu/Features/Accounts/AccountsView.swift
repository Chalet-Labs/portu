import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI

struct AccountsView: View {
    let store: StoreOf<AppFeature>

    @Query(sort: \Account.name) private var accounts: [Account]
    @Environment(\.modelContext) private var modelContext

    @State private var sortOrder: [KeyPathComparator<AccountRowData>] = [
        KeyPathComparator(\.name)
    ]

    private var accountInputs: [AccountInput] {
        accounts.map { account in
            AccountInput(
                id: account.id,
                name: account.name,
                kind: account.kind,
                exchangeType: account.exchangeType,
                dataSource: account.dataSource,
                group: account.group,
                isActive: account.isActive,
                lastSyncError: account.lastSyncError,
                totalBalance: account.positions.reduce(Decimal.zero) { $0 + $1.netUSDValue },
                firstAddress: account.addresses.first?.address)
        }
    }

    private var rows: [AccountRowData] {
        let mapped = AccountsFeature.mapAccountRows(from: accountInputs)
        let filtered = AccountsFeature.filterAccountRows(
            mapped,
            searchText: store.accounts.searchText,
            filterGroup: store.accounts.filterGroup,
            showInactive: store.accounts.showInactive)
        return filtered.sorted(using: sortOrder)
    }

    private var allGroups: [String] {
        AccountsFeature.extractGroups(from: accountInputs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PortuTheme.dashboardContentSpacing) {
            DashboardPageHeader("Accounts")
            toolbar
            accountTable
                .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
        }
        .padding(DashboardStyle.pagePadding)
        .dashboardPage()
        .sheet(item: Binding(
            get: { store.accounts.accountSheetMode },
            set: { if $0 == nil { store.send(.accounts(.accountSheetDismissed)) } })) { mode in
                accountSheet(for: mode)
                    .environment(\.colorScheme, .dark)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            DashboardSearchField(placeholder: "Search accounts...", text: Binding(
                get: { store.accounts.searchText },
                set: { store.send(.accounts(.searchTextChanged($0))) }))
                .frame(width: 220)

            Picker("Group", selection: Binding(
                get: { store.accounts.filterGroup },
                set: { store.send(.accounts(.filterGroupChanged($0))) })) {
                    Text("All Groups").tag(nil as String?)
                    ForEach(allGroups, id: \.self) { group in
                        Text(group).tag(group as String?)
                    }
                }
                .frame(width: 150)
                .dashboardControl()

            Toggle("Show Inactive", isOn: Binding(
                get: { store.accounts.showInactive },
                set: { _ in store.send(.accounts(.showInactiveToggled)) }))
                .font(.caption)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .dashboardControl()

            Spacer()

            Button("Bulk Import") {}
                .disabled(true)
                .help("Coming soon")
                .dashboardControl()

            Button("Add Account", systemImage: "plus") {
                store.send(.accounts(.addAccountTapped))
            }
            .dashboardControl()
        }
        .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
    }

    @ViewBuilder
    private func accountSheet(for mode: AccountSheetMode) -> some View {
        switch mode {
        case .add:
            AddAccountSheet()

        case let .edit(accountID):
            if let account = accounts.first(where: { $0.id == accountID }) {
                AddAccountSheet(
                    mode: mode,
                    account: account,
                    isSyncing: accountIsSyncing(account.id),
                    canSync: account.isSyncable,
                    isSyncBlocked: store.syncStatus.isSyncing && store.syncingAccountID != account.id,
                    onSync: { id in store.send(.accountSyncTapped(id)) })
            } else {
                VStack(spacing: 12) {
                    Text("Account not found")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(PortuTheme.dashboardText)
                    Button("Close") {
                        store.send(.accounts(.accountSheetDismissed))
                    }
                }
                .frame(width: 420, height: 180)
                .background(PortuTheme.dashboardPanelBackground)
            }
        }
    }

    // MARK: - Table

    private var accountTable: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.isActive ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(row.name)
                        .fontWeight(.medium)
                        .foregroundStyle(row.isActive ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
                }
            }
            .width(min: 100, ideal: 150)

            TableColumn("Group", value: \.group)
                .width(min: 60, ideal: 80)

            TableColumn("Address") { row in
                Text(row.address)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .textSelection(.enabled)
                    .help(row.address)
            }
            .width(min: 260, ideal: 420)

            TableColumn("Type") { row in
                CapsuleBadge(row.type)
            }
            .width(min: 60, ideal: 80)

            TableColumn("USD Balance", value: \.balance) { row in
                VStack(alignment: .trailing) {
                    Text(row.balance, format: .currency(code: "USD"))
                        .font(DashboardStyle.monoTableFont)
                    if let error = row.lastSyncError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(PortuTheme.dashboardWarning)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 80, ideal: 120)

            TableColumn("Actions") { row in
                HStack(spacing: 6) {
                    Button {
                        store.send(.accounts(.editAccountTapped(row.id)))
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit account")
                    .accessibilityLabel("Edit account")

                    Button {
                        store.send(.accountSyncTapped(row.id))
                    } label: {
                        if rowIsSyncing(row) {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.62)
                                .tint(PortuTheme.dashboardGold)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .frame(width: 18, height: 18)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(rowSyncDisabled(row))
                    .help(rowSyncHelp(row))
                    .accessibilityLabel("Sync account")
                }
            }
            .width(min: 78, ideal: 92)
        }
        .dashboardTable()
        .contextMenu(forSelectionType: AccountRowData.ID.self) { selection in
            if let id = selection.first, let account = accounts.first(where: { $0.id == id }) {
                Button("Edit") {
                    store.send(.accounts(.editAccountTapped(id)))
                }
                Button("Sync") {
                    store.send(.accountSyncTapped(id))
                }
                .disabled(!account.isSyncable || store.syncStatus.isSyncing)
                Divider()
                Button(account.isActive ? "Deactivate" : "Activate") {
                    account.isActive.toggle()
                    try? modelContext.save()
                }
                Divider()
                Button("Delete", role: .destructive) {
                    let isExchange = account.kind == .exchange
                    modelContext.delete(account)
                    try? modelContext.save()
                    if isExchange {
                        AccountSheetSaveCoordinator.deleteExchangeCredentials(id, secretStore: LocalSecretStore())
                    }
                }
            }
        }
    }

    private func rowSyncDisabled(_ row: AccountRowData) -> Bool {
        !row.isSyncable || store.syncStatus.isSyncing
    }

    private func rowIsSyncing(_ row: AccountRowData) -> Bool {
        accountIsSyncing(row.id)
    }

    private func accountIsSyncing(_ accountID: UUID) -> Bool {
        store.syncStatus.isSyncing && store.syncingAccountID == accountID
    }

    private func rowSyncHelp(_ row: AccountRowData) -> String {
        if store.syncStatus.isSyncing {
            return "Another sync is already running."
        }
        if row.isActive == false {
            return "Inactive accounts cannot be synced."
        }
        if row.dataSource == .manual {
            return "Manual accounts do not sync."
        }
        return "Sync this account."
    }
}
