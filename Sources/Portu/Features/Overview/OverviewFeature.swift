import Foundation
import PortuCore

struct OverviewAssetCandidate: Equatable, Identifiable {
    let id: UUID
    let symbol: String
    let name: String
    let category: AssetCategory
    let coinGeckoId: String
    let logoURL: String?

    @MainActor
    static func fromAssets(
        _ assets: [Asset],
        overrides: [TokenPricingOverrideSnapshot]) -> [OverviewAssetCandidate] {
        let overrideMap = TokenPricingOverrideFeature.overridesByAssetId(overrides)
        return assets.compactMap { asset -> OverviewAssetCandidate? in
            let coinGeckoId = TokenIdentityMappingFeature.normalizedProviderID(
                overrideMap[asset.id]?.coinGeckoIdOverride)
                ?? TokenIdentityMappingFeature.normalizedProviderID(asset.coinGeckoId)
            guard let coinGeckoId else { return nil }
            return OverviewAssetCandidate(
                id: asset.id,
                symbol: asset.symbol,
                name: asset.name,
                category: asset.category,
                coinGeckoId: coinGeckoId,
                logoURL: asset.logoURL)
        }
    }
}

enum OverviewSummaryLabels {
    static let genericMajorsTitle = "Majors"

    static func majorCategoryTitle(categories: [PortfolioCategorySnapshot]) -> String {
        let title = categories
            .filter { PortfolioCategoryDefaults.majorCategoryIDs.contains($0.id) }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                let nameOrder = $0.name.localizedStandardCompare($1.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map(\.name)
            .joined(separator: " / ")
        return title.isEmpty ? genericMajorsTitle : title
    }
}

struct OverviewAssetSlice: Equatable, Identifiable {
    let id: String
    let label: String
    let value: Decimal
    /// `nil` shows "—" (F4: the list total is not positive).
    let displayPercent: Int?
    let colorIndex: Int
    let logoURL: String?
}

struct OverviewPriceRowData: Equatable, Identifiable {
    let id: String
    let assetId: UUID?
    let symbol: String
    let name: String
    let coinGeckoId: String?
    let price: Decimal?
    let change24h: Decimal?
    let isWatchlisted: Bool
    let logoURL: String?
}

enum OverviewPriceCountdown {
    static func secondsRemaining(
        lastPriceUpdate: Date?,
        refreshInterval: TimeInterval,
        now: Date) -> Int {
        let fallback = max(0, Int(refreshInterval.rounded(.up)))
        guard let lastPriceUpdate else { return fallback }

        let nextUpdate = lastPriceUpdate.addingTimeInterval(refreshInterval)
        return max(0, Int(ceil(nextUpdate.timeIntervalSince(now))))
    }
}

enum OverviewWatchlistStore {
    static let key = "OverviewWatchlistCoinGeckoIDs"

    static func decode(_ rawValue: String) -> [String] {
        guard
            let data = rawValue.data(using: .utf8),
            let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return normalizedUniqueIDs(ids)
    }

    static func encode(_ ids: [String]) -> String {
        let normalized = normalizedUniqueIDs(ids)
        guard
            let data = try? JSONEncoder().encode(normalized),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return string
    }

    static func add(_ id: String, to ids: [String]) -> [String] {
        normalizedUniqueIDs(ids + [id])
    }

    static func remove(_ id: String, from ids: [String]) -> [String] {
        let target = TokenIdentityMappingFeature.normalizedProviderID(id)
        return normalizedUniqueIDs(ids).filter { $0 != target }
    }

    static func normalizedUniqueIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for id in ids {
            guard
                let normalized = TokenIdentityMappingFeature.normalizedProviderID(id),
                !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }
}

enum OverviewFeature {
    static let assetResidualSliceID = "asset-residual"
    static let categoryResidualSliceID = "category-residual"
    private static let reservedMarketSymbols: [String: Set<String>] = [
        "BTC": ["bitcoin"],
        "ETH": ["ether", "ethereum"],
        "USDC": ["usd coin", "usdc"],
        "USDT": ["tether", "tether usd", "usdt"],
        "DAI": ["dai"],
        "SOL": ["solana"],
        "BNB": ["bnb", "binance coin"]
    ]

    static func assetCandidatesByCoinGeckoId(
        from assets: [OverviewAssetCandidate]) -> [String: OverviewAssetCandidate] {
        var candidates: [String: OverviewAssetCandidate] = [:]

        for asset in assets {
            guard let coinGeckoId = TokenIdentityMappingFeature.normalizedProviderID(asset.coinGeckoId) else { continue }

            if let existing = candidates[coinGeckoId] {
                candidates[coinGeckoId] = preferredAssetCandidate(asset, over: existing) ? asset : existing
            } else {
                candidates[coinGeckoId] = asset
            }
        }

        return candidates
    }

    static func watchlistSuggestions(
        assets: [OverviewAssetCandidate],
        watchlistIDs: [String],
        query: String,
        limit: Int = 5) -> [OverviewAssetCandidate] {
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty else { return [] }

        let existing = Set(OverviewWatchlistStore.normalizedUniqueIDs(watchlistIDs))
        return assetCandidatesByCoinGeckoId(from: assets)
            .filter { coinGeckoId, asset in
                !existing.contains(coinGeckoId)
                    && (asset.symbol.localizedCaseInsensitiveContains(searchQuery)
                        || asset.name.localizedCaseInsensitiveContains(searchQuery)
                        || coinGeckoId.localizedCaseInsensitiveContains(searchQuery)
                        || asset.coinGeckoId.localizedCaseInsensitiveContains(searchQuery))
            }
            .map(\.value)
            .sorted {
                if $0.symbol == $1.symbol {
                    return $0.name < $1.name
                }
                return $0.symbol < $1.symbol
            }
            .prefix(max(limit, 0))
            .map(\.self)
    }

    struct SliceInput {
        let id: String
        let label: String
        let value: Decimal
        let logoURL: String?
    }

    static func assetAggregateKey(
        for token: TokenEntry,
        priceID: String?) -> String {
        let normalizedSymbol = token.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let priceID = TokenIdentityMappingFeature.normalizedHistoricalPriceID(priceID) {
            return "price:\(priceID):symbol:\(normalizedSymbol)"
        }
        return "asset:\(token.assetId.uuidString)"
    }

    private static func preferredAssetCandidate(
        _ candidate: OverviewAssetCandidate,
        over existing: OverviewAssetCandidate) -> Bool {
        if candidate.symbol == existing.symbol {
            return candidate.name < existing.name
        }
        return candidate.symbol < existing.symbol
    }

    static func displayLabel(
        symbol: String,
        name: String,
        priceID: String?) -> String {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol = trimmedSymbol.uppercased()
        guard
            TokenIdentityMappingFeature.nonOnchainPriceID(priceID) == nil,
            let canonicalNames = reservedMarketSymbols[normalizedSymbol],
            !trimmedName.isEmpty
        else {
            return trimmedSymbol.isEmpty ? trimmedName : trimmedSymbol
        }

        let normalizedName = trimmedName.lowercased()
        if canonicalNames.contains(normalizedName) || normalizedName == normalizedSymbol.lowercased() {
            return trimmedSymbol
        }
        return trimmedName
    }
}
