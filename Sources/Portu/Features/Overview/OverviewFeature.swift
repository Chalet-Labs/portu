// swiftlint:disable file_length

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
    static func fromAssets(_ assets: [Asset]) -> [OverviewAssetCandidate] {
        fromAssets(assets, overrides: [])
    }

    @MainActor
    static func fromAssets(
        _ assets: [Asset],
        overrides: [TokenPricingOverrideSnapshot]) -> [OverviewAssetCandidate] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        return assets.compactMap { asset -> OverviewAssetCandidate? in
            let coinGeckoId = OverviewWatchlistStore.normalizedID(
                overrideMap[asset.id]?.coinGeckoIdOverride)
                ?? OverviewWatchlistStore.normalizedID(asset.coinGeckoId)
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
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                let nameOrder = $0.name.localizedStandardCompare($1.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
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
    let displayPercent: Int
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
        let target = normalize(id)
        return normalizedUniqueIDs(ids).filter { $0 != target }
    }

    static func normalizedUniqueIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for id in ids {
            let normalized = normalize(id)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }

    static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = normalize(id)
        return normalized.isEmpty ? nil : normalized
    }

    static func normalize(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum OverviewFeature {
    private static let assetResidualSliceID = "asset-residual"
    private static let categoryResidualSliceID = "category-residual"
    private static let reservedMarketSymbols: [String: Set<String>] = [
        "BTC": ["bitcoin"],
        "ETH": ["ether", "ethereum"],
        "USDC": ["usd coin", "usdc"],
        "USDT": ["tether", "tether usd", "usdt"],
        "DAI": ["dai"],
        "SOL": ["solana"],
        "BNB": ["bnb", "binance coin"]
    ]

    private struct AssetAggregate {
        let key: String
        var assetIds: Set<UUID>
        var symbol: String
        var name: String
        var category: AssetCategory
        var portfolioCategory: PortfolioCategorySnapshot
        var coinGeckoId: String?
        var priceID: String?
        var value: Decimal
        var amount: Decimal
        var logoURL: String?

        var fallbackPrice: Decimal? {
            guard amount > 0 else { return nil }
            return value / amount
        }

        var assetId: UUID {
            guard let id = assetIds.min(by: { $0.uuidString < $1.uuidString }) else {
                preconditionFailure("AssetAggregate requires at least one asset id")
            }
            return id
        }

        var rowID: String {
            assetIds.count == 1 ? assetId.uuidString : key
        }
    }

    static func topAssetSlices(
        from tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot] = [],
        limit: Int = 5) -> [OverviewAssetSlice] {
        let aggregates = sortedAssetAggregates(from: tokens, prices: prices, overrides: overrides)
        let visibleCount = max(limit, 0)
        var sliceInputs = aggregates.prefix(visibleCount).map {
            SliceInput(id: $0.rowID, label: $0.symbol, value: $0.value, logoURL: $0.logoURL)
        }

        let otherValue = aggregates.dropFirst(visibleCount).reduce(Decimal.zero) { $0 + $1.value }
        if otherValue > 0 {
            sliceInputs.append(SliceInput(id: assetResidualSliceID, label: "other", value: otherValue, logoURL: nil))
        }

        return makeSlices(from: sliceInputs)
    }

    static func categorySlices(
        from tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot] = [],
        limit: Int = 6) -> [OverviewAssetSlice] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var values: [PortfolioCategorySnapshot: Decimal] = [:]
        for token in tokens where token.role.isPositive {
            values[token.portfolioCategory, default: 0] += resolvedValue(
                for: token,
                prices: prices,
                override: overrideMap[token.assetId])
        }

        let sortedValues = values
            .filter { $0.value > 0 }
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                if $0.key.sortOrder != $1.key.sortOrder {
                    return $0.key.sortOrder < $1.key.sortOrder
                }
                let nameOrder = $0.key.name.localizedStandardCompare($1.key.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return $0.key.id.uuidString < $1.key.id.uuidString
            }

        let visibleCount = max(limit, 0)
        var inputs = sortedValues
            .prefix(visibleCount)
            .map { category, value in
                SliceInput(id: category.id.uuidString, label: category.name, value: value, logoURL: nil)
            }

        let otherValue = sortedValues.dropFirst(visibleCount).reduce(Decimal.zero) { $0 + $1.value }
        if otherValue > 0 {
            inputs.append(SliceInput(id: categoryResidualSliceID, label: "other", value: otherValue, logoURL: nil))
        }

        return makeSlices(from: inputs)
    }

    static func assetCandidatesByCoinGeckoId(
        from assets: [OverviewAssetCandidate]) -> [String: OverviewAssetCandidate] {
        var candidates: [String: OverviewAssetCandidate] = [:]

        for asset in assets {
            guard let coinGeckoId = OverviewWatchlistStore.normalizedID(asset.coinGeckoId) else { continue }

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

    static func portfolioTotalValue(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot],
        settings: TokenDashboardSettings = .defaults) -> Decimal {
        let mappedTokens = TokenSettingsFeature.applyIdentityMappings(
            to: tokens,
            mappings: mappings,
            overrides: overrides)
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        let dashboardTokens = TokenSettingsFeature.dashboardEligibleTokens(
            tokens: mappedTokens,
            prices: prices,
            overrideMap: overrideMap,
            settings: settings)

        return dashboardTokens.reduce(Decimal.zero) { total, token in
            let value = OverviewPositionPricing.tokenValue(
                token: token,
                prices: prices,
                override: overrideMap[token.assetId])
            if token.role.isBorrow {
                return total - value
            }
            return token.role.isPositive ? total + value : total
        }
    }

    static func priceRows(
        tokens: [TokenEntry],
        assets: [OverviewAssetCandidate],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        watchlistIDs: [String],
        overrides: [TokenPricingOverrideSnapshot] = [],
        portfolioLimit: Int = 10) -> [OverviewPriceRowData] {
        priceRows(
            tokens: tokens,
            assetsByCoinGeckoId: assetCandidatesByCoinGeckoId(from: assets),
            prices: prices,
            changes24h: changes24h,
            watchlistIDs: watchlistIDs,
            overrides: overrides,
            portfolioLimit: portfolioLimit)
    }

    static func priceRows(
        tokens: [TokenEntry],
        assetsByCoinGeckoId: [String: OverviewAssetCandidate],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        watchlistIDs: [String],
        overrides: [TokenPricingOverrideSnapshot] = [],
        portfolioLimit: Int = 10) -> [OverviewPriceRowData] {
        let watchlist = OverviewWatchlistStore.normalizedUniqueIDs(watchlistIDs)
        let watchlistSet = Set(watchlist)

        var rows: [OverviewPriceRowData] = []
        var seenRowIDs: Set<String> = []
        var portfolioCoinGeckoIDs: Set<String> = []

        for aggregate in sortedAssetAggregates(from: tokens, prices: prices, overrides: overrides).prefix(max(portfolioLimit, 0)) {
            let priceID = TokenIdentityMappingFeature.normalizedProviderID(aggregate.priceID)
            let coinGeckoId = TokenIdentityMappingFeature.nonZapperPriceID(priceID)
            let rowID = aggregate.rowID
            guard !seenRowIDs.contains(rowID) else {
                continue
            }
            seenRowIDs.insert(rowID)
            if let coinGeckoId {
                portfolioCoinGeckoIDs.insert(coinGeckoId)
            }
            rows.append(OverviewPriceRowData(
                id: rowID,
                assetId: aggregate.assetId,
                symbol: aggregate.symbol,
                name: aggregate.name,
                coinGeckoId: coinGeckoId,
                price: displayPrice(for: aggregate, prices: prices),
                change24h: priceID.flatMap { changes24h[$0] },
                isWatchlisted: coinGeckoId.map { watchlistSet.contains($0) } ?? false,
                logoURL: aggregate.logoURL))
        }

        for coinGeckoId in watchlist where !portfolioCoinGeckoIDs.contains(coinGeckoId) && !seenRowIDs.contains(coinGeckoId) {
            seenRowIDs.insert(coinGeckoId)
            if let asset = assetsByCoinGeckoId[coinGeckoId] {
                rows.append(OverviewPriceRowData(
                    id: coinGeckoId,
                    assetId: asset.id,
                    symbol: asset.symbol,
                    name: asset.name,
                    coinGeckoId: coinGeckoId,
                    price: prices[coinGeckoId],
                    change24h: changes24h[coinGeckoId],
                    isWatchlisted: true,
                    logoURL: asset.logoURL))
            } else {
                rows.append(OverviewPriceRowData(
                    id: coinGeckoId,
                    assetId: nil,
                    symbol: coinGeckoId,
                    name: coinGeckoId,
                    coinGeckoId: coinGeckoId,
                    price: prices[coinGeckoId],
                    change24h: changes24h[coinGeckoId],
                    isWatchlisted: true,
                    logoURL: nil))
            }
        }

        return rows
    }

    private struct SliceInput {
        let id: String
        let label: String
        let value: Decimal
        let logoURL: String?
    }

    private static func makeSlices(from inputs: [SliceInput]) -> [OverviewAssetSlice] {
        let percentages = displayPercentages(for: inputs.map(\.value))
        return zip(inputs.indices, inputs).map { index, input in
            OverviewAssetSlice(
                id: input.id,
                label: input.label,
                value: input.value,
                displayPercent: percentages[index],
                colorIndex: index,
                logoURL: input.logoURL)
        }
    }

    private static func sortedAssetAggregates(
        from tokens: [TokenEntry],
        prices: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot] = []) -> [AssetAggregate] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var aggregates: [String: AssetAggregate] = [:]

        for token in tokens where token.role.isPositive {
            let override = overrideMap[token.assetId]
            let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override)
            let key = assetAggregateKey(for: token, priceID: priceID)
            var aggregate = aggregates[key] ?? AssetAggregate(
                key: key,
                assetIds: [token.assetId],
                symbol: displayLabel(symbol: token.symbol, name: token.name, priceID: priceID),
                name: token.name,
                category: token.category,
                portfolioCategory: token.portfolioCategory,
                coinGeckoId: OverviewWatchlistStore.normalizedID(token.coinGeckoId)
                    ?? TokenIdentityMappingFeature.nonZapperPriceID(priceID),
                priceID: priceID,
                value: 0,
                amount: 0,
                logoURL: token.logoURL)
            aggregate.assetIds.insert(token.assetId)
            aggregate.coinGeckoId = aggregate.coinGeckoId
                ?? OverviewWatchlistStore.normalizedID(token.coinGeckoId)
                ?? TokenIdentityMappingFeature.nonZapperPriceID(priceID)
            aggregate.priceID = aggregate.priceID ?? priceID
            aggregate.logoURL = aggregate.logoURL ?? token.logoURL
            aggregate.value += resolvedValue(for: token, prices: prices, override: override)
            if token.amount > 0 {
                aggregate.amount += token.amount
            }
            aggregates[key] = aggregate
        }

        return aggregates.values
            .filter { $0.value > 0 }
            .sorted {
                if $0.value == $1.value {
                    let symbolOrder = $0.symbol.localizedStandardCompare($1.symbol)
                    if symbolOrder != .orderedSame {
                        return symbolOrder == .orderedAscending
                    }

                    let nameOrder = $0.name.localizedStandardCompare($1.name)
                    if nameOrder != .orderedSame {
                        return nameOrder == .orderedAscending
                    }

                    return $0.rowID < $1.rowID
                }
                return $0.value > $1.value
            }
    }

    private static func assetAggregateKey(
        for token: TokenEntry,
        priceID: String?) -> String {
        let normalizedSymbol = token.symbol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let priceID = TokenIdentityMappingFeature.normalizedProviderID(priceID) {
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

    private static func resolvedValue(
        for token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        OverviewPositionPricing.tokenValue(token: token, prices: prices, override: override)
    }

    private static func displayPrice(
        for aggregate: AssetAggregate,
        prices: [String: Decimal]) -> Decimal? {
        guard let priceID = TokenIdentityMappingFeature.normalizedProviderID(aggregate.priceID) else {
            return aggregate.fallbackPrice
        }
        guard let price = prices[priceID] else { return nil }
        if
            OnchainTokenIdentity(historicalPriceID: priceID) == nil
            || OverviewPositionPricing.isPlausible(price: price, amount: aggregate.amount, usdValue: aggregate.value) {
            return price
        }
        return aggregate.fallbackPrice
    }

    private static func displayLabel(
        symbol: String,
        name: String,
        priceID: String?) -> String {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSymbol = trimmedSymbol.uppercased()
        guard
            TokenIdentityMappingFeature.nonZapperPriceID(priceID) == nil,
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

    private static func displayPercentages(for values: [Decimal]) -> [Int] {
        let total = values.reduce(Decimal.zero, +)
        guard total > 0 else { return Array(repeating: 0, count: values.count) }

        var percentages = values.map { value in
            let ratio = NSDecimalNumber(decimal: value / total).doubleValue
            return Int((ratio * 100).rounded())
        }

        let residual = 100 - percentages.reduce(0, +)
        if residual != 0, let residualIndex = values.indices.max(by: { values[$0] < values[$1] }) {
            percentages[residualIndex] += residual
        }

        return percentages
    }
}
