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
        .sheet(isPresented: Binding(
            get: { store.accounts.showAddSheet },
            set: { store.send(.accounts(.addSheetPresented($0))) })) {
                AddAccountSheet()
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
                store.send(.accounts(.addSheetPresented(true)))
            }
            .dashboardControl()
        }
        .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
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
            }
            .width(min: 100, ideal: 160)

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
        }
        .dashboardTable()
        .contextMenu(forSelectionType: AccountRowData.ID.self) { selection in
            if let id = selection.first, let account = accounts.first(where: { $0.id == id }) {
                Button(account.isActive ? "Deactivate" : "Activate") {
                    account.isActive.toggle()
                    try? modelContext.save()
                }
                Divider()
                Button("Delete", role: .destructive) {
                    modelContext.delete(account)
                    try? modelContext.save()
                }
            }
        }
    }
}
