// Sources/Portu/Features/AllAssets/AssetsTab.swift
import SwiftUI
import SwiftData
import PortuCore
import PortuUI

struct AssetsTab: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<PositionToken> { $0.position?.account?.isActive == true })
    private var allTokens: [PositionToken]

    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\AssetRowData.value, order: .reverse)]
    @State private var grouping: Grouping = .none

    // MARK: - Grouping

    enum Grouping: String, CaseIterable {
        case none = "None"
        case category = "Category"
        case priceSource = "Price Source"
    }

    // MARK: - Row data

    struct AssetRowData: Identifiable {
        let id: UUID
        let symbol: String
        let name: String
        let category: AssetCategory
        let netAmount: Decimal
        let price: Decimal
        let value: Decimal
        let hasLivePrice: Bool
    }

    /// Aggregate tokens by Asset.id, compute net amount
    private var rows: [AssetRowData] {
        var assetTokens: [UUID: (asset: Asset, positive: Decimal, borrow: Decimal,
                                  positiveUSD: Decimal, borrowUSD: Decimal)] = [:]

        for token in allTokens {
            guard let asset = token.asset else { continue }
            if token.role.isReward { continue }

            var entry = assetTokens[asset.id] ?? (asset, 0, 0, 0, 0)
            if token.role.isBorrow {
                entry.borrow += token.amount
                entry.borrowUSD += token.usdValue
            } else if token.role.isPositive {
                entry.positive += token.amount
                entry.positiveUSD += token.usdValue
            }
            assetTokens[asset.id] = entry
        }

        return assetTokens.values.compactMap { entry in
            let netAmount = entry.positive - entry.borrow
            let hasLive = entry.asset.coinGeckoId.flatMap { appState.prices[$0] } != nil

            let price: Decimal
            let value: Decimal

            if let cgId = entry.asset.coinGeckoId, let livePrice = appState.prices[cgId] {
                price = livePrice
                value = netAmount * livePrice
            } else {
                // Sync-time fallback: weighted average price
                if entry.positive > 0 {
                    price = entry.positiveUSD / entry.positive
                } else if entry.borrow > 0 {
                    price = entry.borrowUSD / entry.borrow
                } else {
                    price = 0
                }
                value = entry.positiveUSD - entry.borrowUSD
            }

            return AssetRowData(
                id: entry.asset.id,
                symbol: entry.asset.symbol,
                name: entry.asset.name,
                category: entry.asset.category,
                netAmount: netAmount,
                price: price,
                value: value,
                hasLivePrice: hasLive
            )
        }
        .filter { searchText.isEmpty || $0.symbol.localizedCaseInsensitiveContains(searchText)
                   || $0.name.localizedCaseInsensitiveContains(searchText) }
        .sorted(using: sortOrder)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            assetTable
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search assets...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Picker("Group", selection: $grouping) {
                ForEach(Grouping.allCases, id: \.self) { g in
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
                Text(row.category.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .width(min: 80, ideal: 100)

            TableColumn("Net Amount", value: \.netAmount) { row in
                Text(row.netAmount, format: .number.precision(.fractionLength(2...8)))
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
        let header = "Symbol,Name,Category,Net Amount,Price,Value"
        let lines = rows.map { row in
            "\(row.symbol),\"\(row.name)\",\(row.category.rawValue),\(row.netAmount),\(row.price),\(row.value)"
        }
        let csv = ([header] + lines).joined(separator: "\n")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "assets.csv"

        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
