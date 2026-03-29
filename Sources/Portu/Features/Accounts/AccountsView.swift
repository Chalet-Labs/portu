// Sources/Portu/Features/Accounts/AccountsView.swift
import SwiftUI
import SwiftData
import PortuCore

struct AccountsView: View {
    @Query(sort: \Account.name) private var accounts: [Account]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var filterGroup: String? = nil
    @State private var showInactive = false
    @State private var showAddSheet = false
    @State private var sortOrder: [KeyPathComparator<AccountRowData>] = [
        KeyPathComparator(\.name)
    ]

    nonisolated private struct AccountRowData: Identifiable, Sendable {
        let id: UUID
        let name: String
        let group: String
        let address: String
        let type: String
        let balance: Decimal
        let isActive: Bool
        let lastSyncError: String?
    }

    private var rows: [AccountRowData] {
        accounts
            .filter { showInactive || $0.isActive }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .filter { filterGroup == nil || $0.group == filterGroup }
            .map { account in
                let balance = account.positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
                let address = account.addresses.first?.address
                    ?? account.exchangeType?.rawValue.capitalized
                    ?? "Manual"

                return AccountRowData(
                    id: account.id,
                    name: account.name,
                    group: account.group ?? "\u{2014}",
                    address: String(address.prefix(16)) + (address.count > 16 ? "\u{2026}" : ""),
                    type: account.kind.rawValue.capitalized,
                    balance: balance,
                    isActive: account.isActive,
                    lastSyncError: account.lastSyncError
                )
            }
            .sorted(using: sortOrder)
    }

    private var allGroups: [String] {
        Array(Set(accounts.compactMap(\.group))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search accounts...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 200)

                // Group filter
                Picker("Group", selection: $filterGroup) {
                    Text("All Groups").tag(nil as String?)
                    ForEach(allGroups, id: \.self) { group in
                        Text(group).tag(group as String?)
                    }
                }
                .frame(width: 150)

                // Status filter
                Toggle("Show Inactive", isOn: $showInactive)

                Spacer()

                // Bulk import placeholder
                Button("Bulk Import") {}
                    .disabled(true)
                    .help("Coming soon")

                Button("Add Account", systemImage: "plus") {
                    showAddSheet = true
                }
            }
            .padding()

            // Table
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { row in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(row.isActive ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(row.name)
                            .fontWeight(.medium)
                            .foregroundStyle(row.isActive ? .primary : .secondary)
                    }
                }
                .width(min: 100, ideal: 150)

                TableColumn("Group", value: \.group)
                    .width(min: 60, ideal: 80)

                TableColumn("Address") { row in
                    Text(row.address)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 160)

                TableColumn("Type") { row in
                    Text(row.type)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                .width(min: 60, ideal: 80)

                TableColumn("USD Balance", value: \.balance) { row in
                    VStack(alignment: .trailing) {
                        Text(row.balance, format: .currency(code: "USD"))
                        if let error = row.lastSyncError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }
                .width(min: 80, ideal: 120)
            }
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
        .navigationTitle("Accounts")
        .sheet(isPresented: $showAddSheet) {
            AddAccountSheet()
        }
    }
}
