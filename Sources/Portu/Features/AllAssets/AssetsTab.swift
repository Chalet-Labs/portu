// Sources/Portu/Features/AllAssets/AssetsTab.swift
import AppKit
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
    @State private var sortColumn: AssetSortColumn = .value
    @State private var sortAscending = false

    /// Map @Query tokens to lightweight entries, aggregate with live prices, filter, sort.
    private var rows: [AssetRowData] {
        let entries = TokenEntry.fromActiveTokens(allTokens)

        let aggregated = AllAssetsFeature.aggregateRows(tokens: entries, prices: store.prices)
        let filtered = AllAssetsFeature.filterRows(aggregated, searchText: store.allAssets.searchText)
        return sortRows(filtered)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            assetTable
        }
        .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            DashboardSearchField(placeholder: "Search assets...", text: Binding(
                get: { store.allAssets.searchText },
                set: { store.send(.allAssets(.searchTextChanged($0))) }))
                .frame(width: 220)

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
                .dashboardControl()

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .dashboardControl()
        }
        .padding(.bottom, 8)
    }

    // MARK: - Table

    private var assetTable: some View {
        VStack(spacing: 0) {
            assetTableHeader

            Divider()
                .overlay(PortuTheme.dashboardStroke)

            if rows.isEmpty {
                ContentUnavailableView(
                    "No assets",
                    systemImage: "bitcoinsign.circle",
                    description: Text("Synced balances will appear here."))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            assetRow(row, index: index)
                        }
                    }
                }
            }
        }
        .dashboardTable()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PortuTheme.dashboardStroke, lineWidth: 1))
    }

    private var assetTableHeader: some View {
        HStack(spacing: 12) {
            sortHeader("Symbol", column: .symbol, width: 96)
            sortHeader("Name", column: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortHeader("Category", column: .category, width: 112)
            sortHeader("Net Amount", column: .netAmount, width: 150, alignment: .trailing, isTrailing: true)
            sortHeader("Price", column: .price, width: 132, alignment: .trailing, isTrailing: true)
            sortHeader("Value", column: .value, width: 140, alignment: .trailing, isTrailing: true)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(PortuTheme.dashboardPanelElevatedBackground)
    }

    private func assetRow(_ row: AssetRowData, index: Int) -> some View {
        NavigationLink(value: row.id) {
            HStack(spacing: 12) {
                Text(row.symbol)
                    .fontWeight(.semibold)
                    .foregroundStyle(PortuTheme.dashboardText)
                    .frame(width: 96, alignment: .leading)

                Text(row.name)
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CapsuleBadge(row.category.rawValue.capitalized)
                    .frame(width: 112, alignment: .leading)

                Text(row.netAmount, format: .number.precision(.fractionLength(2 ... 8)))
                    .font(DashboardStyle.monoTableFont)
                    .foregroundStyle(row.netAmount < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardText)
                    .frame(width: 150, alignment: .trailing)

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(row.price, format: .currency(code: "USD"))
                        .font(DashboardStyle.monoTableFont)
                    if !row.hasLivePrice {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(PortuTheme.dashboardGold)
                            .help("Sync-time price -- no live data")
                    }
                }
                .frame(width: 132, alignment: .trailing)

                Text(row.value, format: .currency(code: "USD"))
                    .font(DashboardStyle.monoTableFont)
                    .foregroundStyle(row.value < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardText)
                    .frame(width: 140, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: PortuTheme.dashboardTableRowHeight + 8)
            .background(index.isMultiple(of: 2) ? Color.clear : PortuTheme.dashboardPanelElevatedBackground.opacity(0.45))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sortHeader(
        _ title: String,
        column: AssetSortColumn,
        width: CGFloat? = nil,
        alignment: Alignment = .leading,
        isTrailing: Bool = false) -> some View {
        Button {
            updateSort(column)
        } label: {
            HStack(spacing: 4) {
                if isTrailing {
                    Spacer(minLength: 0)
                }
                Text(title.uppercased())
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                if !isTrailing {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
        .font(DashboardStyle.labelFont)
        .foregroundStyle(sortColumn == column ? PortuTheme.dashboardText : PortuTheme.dashboardSecondaryText)
        .help("Sort by \(title)")
    }

    private func updateSort(_ column: AssetSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = column.defaultAscending
        }
    }

    private func sortRows(_ rows: [AssetRowData]) -> [AssetRowData] {
        rows.sorted { lhs, rhs in
            let result = compare(lhs, rhs, by: sortColumn)
            if result == .orderedSame {
                return lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol) == .orderedAscending
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private func compare(
        _ lhs: AssetRowData,
        _ rhs: AssetRowData,
        by column: AssetSortColumn) -> ComparisonResult {
        switch column {
        case .symbol:
            lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol)
        case .name:
            lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .category:
            lhs.category.rawValue.localizedCaseInsensitiveCompare(rhs.category.rawValue)
        case .netAmount:
            compare(lhs.netAmount, rhs.netAmount)
        case .price:
            compare(lhs.price, rhs.price)
        case .value:
            compare(lhs.value, rhs.value)
        }
    }

    private func compare(_ lhs: Decimal, _ rhs: Decimal) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
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

private enum AssetSortColumn {
    case symbol
    case name
    case category
    case netAmount
    case price
    case value

    var defaultAscending: Bool {
        switch self {
        case .symbol, .name, .category:
            true
        case .netAmount, .price, .value:
            false
        }
    }
}
