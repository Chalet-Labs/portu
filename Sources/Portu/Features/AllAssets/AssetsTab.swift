import AppKit
import ComposableArchitecture
import PortuCore
import PortuUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AssetsTab: View {
    let store: StoreOf<AppFeature>
    @Environment(AppState.self) private var appState
    @Environment(\.historicalDisplayPrices) private var historicalDisplayPrices
    var sources = ValuationSources()
    @Query private var allTokens: [PositionToken]
    @Query(sort: [SortDescriptor(\PortfolioCategory.sortOrder), SortDescriptor(\PortfolioCategory.name)])
    private var portfolioCategories: [PortfolioCategory]
    @Query(sort: \CategorySymbolRule.normalizedSymbol)
    private var categoryRules: [CategorySymbolRule]

    @State private var exportError: String?
    @State private var sortColumn: AssetSortColumn = .value
    @State private var sortAscending = false

    private var currencyCode: String {
        appState.selectedCurrency.displayCode
    }

    // MARK: - Body

    var body: some View {
        let inputs = sources.allAssets(
            allTokens,
            categoryResolver: PortfolioCategoryResolver.live(categories: portfolioCategories, rules: categoryRules))
        let data = AllAssetsFeature.assets(
            inputs.context,
            searchText: store.allAssets.searchText,
            liveDisplayPrices: store.liveDisplayPrices,
            historicalDisplayPrices: historicalDisplayPrices)
        let entries = data.entries(sortedBy: sortColumn, ascending: sortAscending)
        VStack(spacing: 0) {
            toolbar(entries.compactMap(\.row))
            assetTable(entries)
        }
        .dashboardCard(horizontalPadding: 10, verticalPadding: 10)
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: {
            if !$0 {
                exportError = nil
            }
        })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Toolbar

    private func toolbar(_ rows: [AssetRowData]) -> some View {
        HStack(spacing: 10) {
            DashboardSearchField(placeholder: "Search assets...", text: Binding(
                get: { store.allAssets.searchText },
                set: { store.send(.allAssets(.searchTextChanged($0))) }))
                .frame(width: 220)

            Spacer()

            Button {
                exportCSV(rows)
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .dashboardControl()
        }
        .padding(.bottom, 8)
    }

    // MARK: - Table

    private func assetTable(_ entries: [AllAssetsTableEntry<AssetRowData>]) -> some View {
        VStack(spacing: 0) {
            assetTableHeader

            Divider()
                .overlay(PortuTheme.dashboardStroke)

            if entries.isEmpty {
                ContentUnavailableView(
                    "No assets",
                    systemImage: "bitcoinsign.circle",
                    description: Text("Synced balances will appear here."))
                    .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            switch entry {
                            case let .row(row):
                                assetRow(row, index: index)
                            case let .hidden(line):
                                hiddenRow(line, index: index)
                            }
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

                CapsuleBadge(row.portfolioCategory.name)
                    .frame(width: 112, alignment: .leading)

                Text(row.netAmount, format: .number.precision(.fractionLength(2 ... 8)))
                    .font(DashboardStyle.monoTableFont)
                    .foregroundStyle(row.netAmount < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardText)
                    .frame(width: 150, alignment: .trailing)

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if let price = row.price {
                        Text(price, format: .currency(code: currencyCode))
                            .font(DashboardStyle.monoTableFont)
                    } else {
                        Text("—")
                            .font(DashboardStyle.monoTableFont)
                            .foregroundStyle(PortuTheme.dashboardSecondaryText)
                    }
                    if !row.hasLivePrice {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(PortuTheme.dashboardGold)
                            .help("Sync-time price -- no live data")
                    }
                }
                .frame(width: 132, alignment: .trailing)

                Text(row.value, format: .currency(code: currencyCode))
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

    /// The hidden-balances line: the last row, its value in the Value column.
    private func hiddenRow(_ line: AllAssetsHiddenRow, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(line.title)
                .foregroundStyle(PortuTheme.dashboardSecondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(line.value, format: .currency(code: currencyCode))
                .font(DashboardStyle.monoTableFont)
                .foregroundStyle(line.value < 0 ? PortuTheme.dashboardWarning : PortuTheme.dashboardSecondaryText)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: PortuTheme.dashboardTableRowHeight + 8)
        .background(index.isMultiple(of: 2) ? Color.clear : PortuTheme.dashboardPanelElevatedBackground.opacity(0.45))
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

    // MARK: - CSV Export

    private func exportCSV(_ rows: [AssetRowData]) {
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
