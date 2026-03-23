import Foundation
import SwiftUI
import PortuUI

struct AssetsTabView: View {
    typealias TableSortComparator = AssetRowComparator

    enum SortColumn: String, CaseIterable {
        case symbol = "Symbol"
        case name = "Name"
        case category = "Category"
        case netAmount = "Net Amount"
        case price = "Price"
        case value = "Value"

        var title: String {
            rawValue
        }

        var comparator: TableSortComparator {
            AssetRowComparator(column: self)
        }
    }

    static let tableColumnTitles = SortColumn.allCases.map(\.title)
    static let defaultSortOrder: [TableSortComparator] = [
        AssetRowComparator(column: .value, order: .reverse),
        AssetRowComparator(column: .symbol)
    ]

    let rows: [AssetTableRow]
    let groups: [AssetRowGroup]
    @Binding var searchText: String
    @Binding var grouping: AllAssetsGrouping

    @State private var isExporting = false
    @State private var sortOrder = Self.defaultSortOrder

    private var exportDocument: CSVDocument {
        Self.makeExportDocument(rows: rows, sortOrder: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("Grouping", selection: $grouping) {
                    ForEach(AllAssetsGrouping.allCases) { grouping in
                        Text(grouping.title).tag(grouping)
                    }
                }
                .frame(maxWidth: 220)

                Spacer()

                Button("Export CSV", systemImage: "square.and.arrow.up") {
                    isExporting = true
                }
            }

            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Assets", systemImage: "tray")
                } description: {
                    Text("Try a different search query or sync more accounts.")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                if groups.count > 1 {
                                    SectionHeader(
                                        group.title,
                                        subtitle: "\(group.rows.count) asset\(group.rows.count == 1 ? "" : "s")"
                                    )
                                }

                                assetTable(group.rows)
                                    .frame(minHeight: tableHeight(for: group.rows.count))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: CSVDocument.csvContentType,
            defaultFilename: "all-assets"
        ) { _ in }
        .searchable(text: $searchText, prompt: "Search assets")
    }

    @ViewBuilder
    private func assetTable(
        _ rows: [AssetTableRow]
    ) -> some View {
        Table(sortedRows(rows), sortOrder: $sortOrder) {
            TableColumn(SortColumn.symbol.title, sortUsing: SortColumn.symbol.comparator) { row in
                Text(row.symbol)
            }
            TableColumn(SortColumn.name.title, sortUsing: SortColumn.name.comparator) { row in
                Text(row.name)
            }
            TableColumn(SortColumn.category.title, sortUsing: SortColumn.category.comparator) { row in
                Text(row.categoryTitle)
            }
            TableColumn(SortColumn.netAmount.title, sortUsing: SortColumn.netAmount.comparator) { row in
                Text(row.netAmount.formatted())
            }
            TableColumn(SortColumn.price.title, sortUsing: SortColumn.price.comparator) { row in
                CurrencyText(row.price)
            }
            TableColumn(SortColumn.value.title, sortUsing: SortColumn.value.comparator) { row in
                CurrencyText(row.value)
            }
        }
    }

    private func sortedRows(
        _ rows: [AssetTableRow]
    ) -> [AssetTableRow] {
        Self.sortedRows(rows, using: sortOrder)
    }

    static func makeExportDocument(
        rows: [AssetTableRow],
        sortOrder: [TableSortComparator]
    ) -> CSVDocument {
        CSVDocument(text: AssetsCSVExporter().makeCSV(rows: sortedRows(rows, using: sortOrder)))
    }

    static func sortedRows(
        _ rows: [AssetTableRow],
        using sortOrder: [TableSortComparator]
    ) -> [AssetTableRow] {
        let effectiveSortOrder = sortOrder.isEmpty ? defaultSortOrder : sortOrder
        return rows.sorted(using: effectiveSortOrder)
    }

    private func tableHeight(
        for rowCount: Int
    ) -> CGFloat {
        max(140, CGFloat(rowCount) * 44)
    }
}

private extension AssetTableRow {
    nonisolated var categoryTitle: String {
        category.rawValue.capitalized
    }
}

struct AssetRowComparator: SortComparator {
    typealias Compared = AssetTableRow

    let column: AssetsTabView.SortColumn
    var order: SortOrder = .forward

    nonisolated func compare(
        _ lhs: AssetTableRow,
        _ rhs: AssetTableRow
    ) -> ComparisonResult {
        let primaryResult: ComparisonResult = switch column {
        case .symbol:
            compareText(lhs.symbol, rhs.symbol)
        case .name:
            compareText(lhs.name, rhs.name)
        case .category:
            compareText(lhs.categoryTitle, rhs.categoryTitle)
        case .netAmount:
            compareDecimal(lhs.netAmount, rhs.netAmount)
        case .price:
            compareDecimal(lhs.price, rhs.price)
        case .value:
            compareDecimal(lhs.value, rhs.value)
        }

        let result = if primaryResult == .orderedSame {
            tieBreak(lhs, rhs)
        } else {
            primaryResult
        }

        guard order == .reverse else {
            return result
        }

        switch result {
        case .orderedAscending:
            return .orderedDescending
        case .orderedDescending:
            return .orderedAscending
        case .orderedSame:
            return .orderedSame
        }
    }

    private nonisolated func compareText(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        lhs.localizedCaseInsensitiveCompare(rhs)
    }

    private nonisolated func compareDecimal(
        _ lhs: Decimal,
        _ rhs: Decimal
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }

        if lhs > rhs {
            return .orderedDescending
        }

        return .orderedSame
    }

    private nonisolated func tieBreak(
        _ lhs: AssetTableRow,
        _ rhs: AssetTableRow
    ) -> ComparisonResult {
        let comparisons = [
            compareText(lhs.symbol, rhs.symbol),
            compareText(lhs.name, rhs.name),
            compareText(lhs.categoryTitle, rhs.categoryTitle),
            compareText(lhs.id, rhs.id)
        ]

        return comparisons.first(where: { $0 != .orderedSame }) ?? .orderedSame
    }
}
