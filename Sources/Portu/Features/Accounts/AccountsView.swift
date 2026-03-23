import SwiftData
import SwiftUI
import PortuCore
import PortuUI

struct AccountsView: View {
    static let navigationTitle = "Accounts"
    static let tableColumnTitles = ["Name", "Group", "Address", "Type", "USD Balance"]

    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @State private var searchText = ""
    @State private var filter: AccountFilter = .all
    @State private var selectedGroup = ""
    @State private var isPresentingAddAccount = false

    private var viewModel: AccountsViewModel {
        let viewModel = AccountsViewModel(accounts: accounts)
        viewModel.searchText = searchText
        viewModel.filter = filter
        viewModel.selectedGroup = selectedGroup.isEmpty ? nil : selectedGroup
        return viewModel
    }

    var body: some View {
        let viewModel = viewModel

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("Status", selection: $filter) {
                    ForEach(AccountFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Picker("Group", selection: $selectedGroup) {
                    Text("All Groups").tag("")
                    ForEach(viewModel.availableGroups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
                .frame(maxWidth: 220)

                Spacer()
            }

            Table(viewModel.visibleRows) {
                TableColumn(Self.tableColumnTitles[0]) { row in
                    Text(row.name)
                        .contextMenu {
                            Button(viewModel.toggleActionTitle(for: row)) {
                                toggleActiveState(for: row, using: viewModel)
                            }
                        }
                }
                TableColumn(Self.tableColumnTitles[1], value: \.groupName)
                TableColumn(Self.tableColumnTitles[2], value: \.secondaryLabel)
                TableColumn(Self.tableColumnTitles[3], value: \.typeLabel)
                TableColumn(Self.tableColumnTitles[4]) { row in
                    CurrencyText(row.usdBalance)
                }
            }
        }
        .padding()
        .searchable(text: $searchText, prompt: "Search accounts")
        .navigationTitle(Self.navigationTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(AddAccountSheet.bulkImportTitle, systemImage: "square.and.arrow.down") {
                }
                .disabled(true)
                .help(AddAccountSheet.bulkImportHelp)

                Button("Add Account", systemImage: "plus") {
                    isPresentingAddAccount = true
                }
            }
        }
        .sheet(isPresented: $isPresentingAddAccount) {
            AddAccountSheet {
                isPresentingAddAccount = false
            }
        }
    }

    private func toggleActiveState(for row: AccountRowModel, using viewModel: AccountsViewModel) {
        do {
            try viewModel.toggleActiveState(for: row.id)
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }
}
