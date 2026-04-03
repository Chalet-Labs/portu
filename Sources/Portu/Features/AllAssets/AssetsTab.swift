// Sources/Portu/Features/AllAssets/AssetsTab.swift
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AssetsTab: View {
    let store: StoreOf<AppFeature>
    @Query private var allTokens: [PositionToken]

    @State private var exportError: String?
    @State private var sortOrder: [KeyPathComparator<AssetRowData>] = [
        KeyPathComparator(\.value, order: .reverse)
    ]

    /// Map @Query tokens to lightweight entries, aggregate with live prices, filter, sort.
    private var rows: [AssetRowData] {
        let entries = TokenEntry.fromActiveTokens(allTokens)

        let aggregated = AllAssetsFeature.aggregateRows(tokens: entries, prices: store.prices)
        let filtered = AllAssetsFeature.filterRows(aggregated, searchText: store.allAssets.searchText)
        return filtered.sorted(using: sortOrder)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            assetTable
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search assets...", text: Binding(
                    get: { store.allAssets.searchText },
                    set: { store.send(.allAssets(.searchTextChanged($0))) }))
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Picker("Group", selection: Binding(
                get: { store.allAssets.grouping },
                set: { store.send(.allAssets(.groupingChanged($0))) })) {
                    ForEach(AssetGrouping.allCases, id: \.self) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Table

    private var assetTable: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Symbol", value: \.symbol) { row in
                NavigationLink(value: row.id) {
                    Text(row.symbol).fontWeight(.medium)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("Name", value: \.name) { row in
                Text(row.name)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Category") { row in
                CapsuleBadge(row.category.rawValue.capitalized)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Net Amount", value: \.netAmount) { row in
                Text(row.netAmount, format: .number.precision(.fractionLength(2 ... 8)))
                    .foregroundStyle(row.netAmount < 0 ? .red : .primary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Price", value: \.price) { row in
                HStack(spacing: 4) {
                    Text(row.price, format: .currency(code: "USD"))
                    if !row.hasLivePrice {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Sync-time price -- no live data")
                    }
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("Value", value: \.value) { row in
                Text(row.value, format: .currency(code: "USD"))
                    .foregroundStyle(row.value < 0 ? .red : .primary)
            }
            .width(min: 80, ideal: 120)
        }
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let csv = AllAssetsFeature.generateCSV(from: rows)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "assets.csv"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
