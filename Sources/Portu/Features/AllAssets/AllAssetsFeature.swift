import ComposableArchitecture
import Foundation
import PortuCore

// MARK: - Supporting Types

enum AssetTab: String, CaseIterable, Equatable, Hashable {
    case assets = "Assets"
    case nfts = "NFTs"
    case platforms = "Platforms"
    case networks = "Networks"
}

enum AssetGrouping: String, CaseIterable, Equatable, Hashable {
    case none = "None"
    case category = "Category"
    case priceSource = "Price Source"
}

/// Row data for asset table display (nonisolated for Sendable KeyPaths).
nonisolated struct AssetRowData: Identifiable {
    let id: UUID
    let symbol: String
    let name: String
    let category: AssetCategory
    let netAmount: Decimal
    let price: Decimal
    let value: Decimal
    let hasLivePrice: Bool
}

/// Lightweight input for row aggregation — decouples from SwiftData models.
struct TokenEntry: Equatable {
    let assetId: UUID
    let symbol: String
    let name: String
    let category: AssetCategory
    let coinGeckoId: String?
    let role: TokenRole
    let amount: Decimal
    let usdValue: Decimal

    /// Convert active PositionTokens to TokenEntries, filtering out tokens without assets or inactive accounts.
    static func fromActiveTokens(_ tokens: [PositionToken]) -> [TokenEntry] {
        tokens.compactMap { token in
            guard let asset = token.asset, token.position?.account?.isActive == true else { return nil }
            return TokenEntry(
                assetId: asset.id, symbol: asset.symbol, name: asset.name,
                category: asset.category, coinGeckoId: asset.coinGeckoId,
                role: token.role, amount: token.amount, usdValue: token.usdValue)
        }
    }
}

// MARK: - AllAssetsFeature

@Reducer
struct AllAssetsFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: AssetTab = .assets
        var searchText: String = ""
        var grouping: AssetGrouping = .none
    }

    enum Action: Equatable {
        case tabSelected(AssetTab)
        case searchTextChanged(String)
        case groupingChanged(AssetGrouping)
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

            case let .groupingChanged(grouping):
                state.grouping = grouping
                return .none
            }
        }
    }

    // MARK: - Pure Functions

    /// Aggregate token entries into display rows, merging live prices where available.
    static func aggregateRows(
        tokens: [TokenEntry],
        prices: [String: Decimal]) -> [AssetRowData] {
        var assetTokens: [UUID: (
            symbol: String,
            name: String,
            category: AssetCategory,
            coinGeckoId: String?,
            positive: Decimal,
            borrow: Decimal,
            positiveUSD: Decimal,
            borrowUSD: Decimal)] = [:]

        for token in tokens {
            if token.role.isReward { continue }

            var entry = assetTokens[token.assetId] ?? (
                token.symbol, token.name, token.category, token.coinGeckoId,
                0, 0, 0, 0)
            entry.coinGeckoId = entry.coinGeckoId ?? token.coinGeckoId

            if token.role.isBorrow {
                entry.borrow += token.amount
                entry.borrowUSD += token.usdValue
            } else if token.role.isPositive {
                entry.positive += token.amount
                entry.positiveUSD += token.usdValue
            }
            assetTokens[token.assetId] = entry
        }

        return assetTokens.map { assetId, entry in
            let netAmount = entry.positive - entry.borrow
            let hasLive = entry.coinGeckoId.flatMap { prices[$0] } != nil

            let price: Decimal
            let value: Decimal

            if let cgId = entry.coinGeckoId, let livePrice = prices[cgId] {
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
                id: assetId,
                symbol: entry.symbol,
                name: entry.name,
                category: entry.category,
                netAmount: netAmount,
                price: price,
                value: value,
                hasLivePrice: hasLive)
        }
    }

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
            "\(csv(row.symbol)),\(csv(row.name)),\(csv(row.category.rawValue)),\(row.netAmount),\(row.price),\(row.value)"
        }
        return ([header] + lines).joined(separator: "\n")
    }
}
