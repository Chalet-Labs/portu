import Foundation
import Testing
import PortuCore
@testable import Portu

@MainActor
@Suite("All Assets Export Tests")
struct AllAssetsExportTests {
    @Test func nftTabShowsComingSoonPlaceholder() {
        #expect(NFTPlaceholderTabView.placeholderText == "NFT tracking coming soon")
    }

    @Test func csvExporterWritesHeaderAndRows() throws {
        let csv = AssetsCSVExporter().makeCSV(rows: [.fixture(symbol: "ETH")])

        #expect(csv.contains("Symbol,Name,Category,Net Amount,Price,Value"))
        #expect(csv.contains("ETH"))
    }

    @Test func contentViewRoutesAllAssetsSectionToAllAssetsWorkspace() {
        #expect(ContentView.destination(for: .allAssets) == .allAssets)
    }

    @Test func assetsTabExposesExpectedSortableColumns() {
        #expect(AssetsTabView.tableColumnTitles == ["Symbol", "Name", "Category", "Net Amount", "Price", "Value"])
        #expect(AssetsTabView.SortColumn.allCases.map(\.title) == AssetsTabView.tableColumnTitles)
    }

    @Test func assetsTabExportDocumentUsesActiveSortOrder() {
        let document = AssetsTabView.makeExportDocument(
            rows: [
                AssetTableRow.fixture(symbol: "ETH", name: "Ethereum"),
                AssetTableRow.fixture(symbol: "BTC", name: "Bitcoin")
            ],
            sortOrder: [AssetsTabView.SortColumn.symbol.comparator]
        )

        let lines = document.text.split(separator: "\n")

        #expect(lines.count == 3)
        #expect(lines[1].hasPrefix("BTC,"))
        #expect(lines[2].hasPrefix("ETH,"))
    }

    @Test(arguments: [
        (
            AssetsTabView.SortColumn.symbol,
            [
                AssetTableRow.fixture(symbol: "ETH", name: "Ethereum"),
                AssetTableRow.fixture(symbol: "BTC", name: "Bitcoin")
            ],
            ["BTC", "ETH"]
        ),
        (
            AssetsTabView.SortColumn.name,
            [
                AssetTableRow.fixture(symbol: "ETH", name: "Ethereum"),
                AssetTableRow.fixture(symbol: "BTC", name: "Bitcoin")
            ],
            ["BTC", "ETH"]
        ),
        (
            AssetsTabView.SortColumn.category,
            [
                AssetTableRow.fixture(symbol: "USDC", category: .stablecoin),
                AssetTableRow.fixture(symbol: "ETH", category: .major)
            ],
            ["ETH", "USDC"]
        ),
        (
            AssetsTabView.SortColumn.netAmount,
            [
                AssetTableRow.fixture(symbol: "ETH", netAmount: 2),
                AssetTableRow.fixture(symbol: "BTC", netAmount: 1)
            ],
            ["BTC", "ETH"]
        ),
        (
            AssetsTabView.SortColumn.price,
            [
                AssetTableRow.fixture(symbol: "ETH", price: 2_000),
                AssetTableRow.fixture(symbol: "BTC", price: 1_000)
            ],
            ["BTC", "ETH"]
        ),
        (
            AssetsTabView.SortColumn.value,
            [
                AssetTableRow.fixture(symbol: "ETH", value: 4_000),
                AssetTableRow.fixture(symbol: "BTC", value: 1_500)
            ],
            ["BTC", "ETH"]
        )
    ])
    func assetsTabSortColumnsProduceSortableComparators(
        column: AssetsTabView.SortColumn,
        rows: [AssetTableRow],
        expectedSymbols: [String]
    ) {
        let sorted = rows.sorted(using: column.comparator)
        #expect(sorted.map(\.symbol) == expectedSymbols)
    }

    @Test func symbolSortComparatorUsesDeterministicSecondaryKeys() {
        let sorted = [
            AssetTableRow.fixture(symbol: "USD", name: "Zeta Dollar"),
            AssetTableRow.fixture(symbol: "USD", name: "Alpha Dollar")
        ]
        .sorted(using: AssetsTabView.SortColumn.symbol.comparator)

        #expect(sorted.map(\.name) == ["Alpha Dollar", "Zeta Dollar"])
    }

    @Test func assetsTabUsesAssetIdentifierForDrillInRows() {
        let assetID = UUID()
        let row = AssetTableRow.fixture(symbol: "ETH", assetID: assetID)

        #expect(AssetsTabView.drillInAssetID(for: row) == assetID)
    }
}

private extension AssetTableRow {
    nonisolated static func fixture(
        symbol: String = "ETH",
        assetID: UUID? = nil,
        name: String? = nil,
        category: AssetCategory = .major,
        netAmount: Decimal = 1.25,
        price: Decimal = 3_200,
        value: Decimal = 4_000
    ) -> AssetTableRow {
        let resolvedName = name ?? (symbol == "ETH" ? "Ethereum" : symbol)

        return AssetTableRow(
            id: "asset:\(symbol)",
            assetID: assetID,
            symbol: symbol,
            name: resolvedName,
            category: category,
            netAmount: netAmount,
            grossValue: 6_400,
            price: price,
            value: value,
            priceSource: .live,
            accountGroups: ["Ungrouped"],
            searchIndex: "\(symbol) \(resolvedName)".lowercased()
        )
    }
}
