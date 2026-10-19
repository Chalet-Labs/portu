import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

enum AssetTab: String, CaseIterable, Equatable, Hashable {
    case assets = "Assets"
    case platforms = "Platforms"
    case networks = "Networks"
}

/// Row data for asset table display (nonisolated for Sendable KeyPaths).
nonisolated struct AssetRowData: Identifiable, Equatable {
    let id: UUID
    let symbol: String
    let name: String
    let category: AssetCategory
    let portfolioCategory: PortfolioCategorySnapshot
    let netAmount: Decimal
    /// The V5 unit price; `nil` (shown "—") when nothing in the row is valued.
    let price: Decimal?
    let value: Decimal
    /// The source of the row's lead token; the clock marks a sync-time price.
    let source: ValuationSource?

    init(
        id: UUID,
        symbol: String,
        name: String,
        category: AssetCategory,
        portfolioCategory: PortfolioCategorySnapshot? = nil,
        netAmount: Decimal,
        price: Decimal?,
        value: Decimal,
        source: ValuationSource?) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.category = category
        self.portfolioCategory = portfolioCategory
            ?? PortfolioCategoryResolver.defaults.resolve(symbol: symbol, legacyCategory: category)
        self.netAmount = netAmount
        self.price = price
        self.value = value
        self.source = source
    }
}

extension AssetRowData {
    /// An asset row in the display currency. Every token of the row shares one asset, so its
    /// symbol, name and categories come from any of them.
    init?(_ row: DashboardRow<UUID>, rate: Decimal) {
        guard let token = row.tokens.first?.token else { return nil }
        let pricing = row.pricing.display(rate: rate)
        self.init(
            id: row.key,
            symbol: token.symbol,
            name: token.name,
            category: token.category,
            portfolioCategory: token.portfolioCategory,
            netAmount: row.totals.netAmount,
            price: pricing.price,
            value: row.displayValue(rate: rate),
            source: pricing.source)
    }
}

// MARK: - AllAssetsFeature

@Reducer
struct AllAssetsFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: AssetTab = .assets
        var searchText: String = ""
    }

    enum Action: Equatable {
        case tabSelected(AssetTab)
        case searchTextChanged(String)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none

            case let .searchTextChanged(text):
                state.searchText = text
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Filter rows by search text (case-insensitive match on symbol or name).
    static func filterRows(
        _ rows: [AssetRowData],
        searchText: String) -> [AssetRowData] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.symbol.localizedCaseInsensitiveContains(searchText)
                || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Generate CSV string from asset rows.
    static func generateCSV(from rows: [AssetRowData]) -> String {
        func csv(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        let header = "Symbol,Name,Category,Net Amount,Price,Value"
        let lines = rows.map { row in
            let price = row.price.map { "\($0)" } ?? ""
            return "\(csv(row.symbol)),\(csv(row.name)),\(csv(row.portfolioCategory.name)),\(row.netAmount),\(price),\(row.value)"
        }
        return ([header] + lines).joined(separator: "\n")
    }
}
