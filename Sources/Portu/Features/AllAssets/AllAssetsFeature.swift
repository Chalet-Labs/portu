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
    let portfolioCategory: PortfolioCategorySnapshot
    let netAmount: Decimal
    let price: Decimal
    let value: Decimal
    let hasLivePrice: Bool

    init(
        id: UUID,
        symbol: String,
        name: String,
        category: AssetCategory,
        portfolioCategory: PortfolioCategorySnapshot? = nil,
        netAmount: Decimal,
        price: Decimal,
        value: Decimal,
        hasLivePrice: Bool) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.category = category
        self.portfolioCategory = portfolioCategory
            ?? PortfolioCategoryResolver.defaults.resolve(symbol: symbol, legacyCategory: category)
        self.netAmount = netAmount
        self.price = price
        self.value = value
        self.hasLivePrice = hasLivePrice
    }
}

/// Accumulator for aggregating token amounts per asset.
struct AssetAccumulator {
    var symbol: String
    var name: String
    var category: AssetCategory
    var portfolioCategory: PortfolioCategorySnapshot = PortfolioCategoryDefaults.fallbackCategory
    var coinGeckoId: String?
    var onchainIdentity: OnchainTokenIdentity?
    var positive: Decimal = 0
    var borrow: Decimal = 0
    var positiveUSD: Decimal = 0
    var borrowUSD: Decimal = 0
}

/// Lightweight input for row aggregation — decouples from SwiftData models.
struct TokenEntry: Equatable {
    let assetId: UUID
    let symbol: String
    let name: String
    let category: AssetCategory
    let portfolioCategory: PortfolioCategorySnapshot
    let coinGeckoId: String?
    let onchainIdentity: OnchainTokenIdentity?
    let role: TokenRole
    let amount: Decimal
    let usdValue: Decimal
    let logoURL: String?

    init(
        assetId: UUID,
        symbol: String,
        name: String,
        category: AssetCategory,
        portfolioCategory: PortfolioCategorySnapshot? = nil,
        coinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity? = nil,
        role: TokenRole,
        amount: Decimal,
        usdValue: Decimal,
        logoURL: String? = nil) {
        self.assetId = assetId
        self.symbol = symbol
        self.name = name
        self.category = category
        self.portfolioCategory = portfolioCategory
            ?? PortfolioCategoryResolver.defaults.resolve(symbol: symbol, legacyCategory: category)
        self.coinGeckoId = coinGeckoId
        self.onchainIdentity = onchainIdentity
        self.role = role
        self.amount = amount
        self.usdValue = usdValue
        self.logoURL = logoURL
    }

    /// Convert active PositionTokens to TokenEntries, filtering out tokens without assets or inactive accounts.
    static func fromActiveTokens(
        _ tokens: [PositionToken],
        categoryResolver: PortfolioCategoryResolver = .defaults) -> [TokenEntry] {
        tokens.compactMap { token in
            guard let asset = token.asset, token.position?.account?.isActive == true else { return nil }
            return TokenEntry(
                assetId: asset.id, symbol: asset.symbol, name: asset.name,
                category: asset.category,
                portfolioCategory: categoryResolver.resolve(symbol: asset.symbol, legacyCategory: asset.category),
                coinGeckoId: asset.coinGeckoId,
                onchainIdentity: OnchainTokenIdentity(chain: asset.upsertChain, contractAddress: asset.upsertContract),
                role: token.role, amount: token.amount, usdValue: token.usdValue,
                logoURL: asset.logoURL)
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
        var assetTokens: [UUID: AssetAccumulator] = [:]

        for token in tokens {
            if token.role.isReward { continue }

            var entry = assetTokens[token.assetId] ?? AssetAccumulator(
                symbol: token.symbol, name: token.name, category: token.category,
                portfolioCategory: token.portfolioCategory,
                coinGeckoId: token.coinGeckoId,
                onchainIdentity: token.onchainIdentity)
            entry.coinGeckoId = entry.coinGeckoId ?? token.coinGeckoId
            entry.onchainIdentity = entry.onchainIdentity ?? token.onchainIdentity

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
                portfolioCategory: entry.portfolioCategory,
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
            "\(csv(row.symbol)),\(csv(row.name)),\(csv(row.portfolioCategory.name)),\(row.netAmount),\(row.price),\(row.value)"
        }
        return ([header] + lines).joined(separator: "\n")
    }
}
