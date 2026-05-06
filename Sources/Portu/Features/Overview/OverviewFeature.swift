import Foundation
import PortuCore

struct OverviewAssetCandidate: Equatable, Identifiable {
    let id: UUID
    let symbol: String
    let name: String
    let category: AssetCategory
    let coinGeckoId: String

    @MainActor
    static func fromAssets(_ assets: [Asset]) -> [OverviewAssetCandidate] {
        assets.compactMap { asset in
            guard let coinGeckoId = asset.coinGeckoId else { return nil }
            return OverviewAssetCandidate(
                id: asset.id,
                symbol: asset.symbol,
                name: asset.name,
                category: asset.category,
                coinGeckoId: coinGeckoId)
        }
    }
}

struct OverviewAssetSlice: Equatable, Identifiable {
    let id: String
    let label: String
    let value: Decimal
    let displayPercent: Int
    let colorIndex: Int
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
}

enum OverviewPriceDisplay {
    static let assetLabelMaxLength = 6
    private static let priceLocale = Locale(identifier: "en_US_POSIX")

    static func assetLabel(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(assetLabelMaxLength))
    }

    static func price(_ price: Decimal) -> String {
        "$ \(formattedNumber(price))"
    }

    private static func formattedNumber(_ price: Decimal) -> String {
        let number = NSDecimalNumber(decimal: price).doubleValue
        return number.formatted(.number
            .locale(priceLocale)
            .grouping(.automatic)
            .precision(.fractionLength(0 ... maximumFractionDigits(for: abs(number)))))
    }

    private static func maximumFractionDigits(for absoluteValue: Double) -> Int {
        if absoluteValue >= 1000 { return 0 }
        if absoluteValue >= 1 { return 4 }
        if absoluteValue >= 0.0001 { return 6 }
        return 8
    }
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

    static func normalize(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum OverviewFeature {
    private struct AssetAggregate {
        let assetId: UUID
        var symbol: String
        var name: String
        var category: AssetCategory
        var coinGeckoId: String?
        var value: Decimal
        var amount: Decimal

        var fallbackPrice: Decimal? {
            guard amount > 0 else { return nil }
            return value / amount
        }
    }

    static func topAssetSlices(
        from tokens: [TokenEntry],
        prices: [String: Decimal],
        limit: Int = 5) -> [OverviewAssetSlice] {
        let aggregates = sortedAssetAggregates(from: tokens, prices: prices)
        let visibleCount = max(limit, 0)
        var sliceInputs = aggregates.prefix(visibleCount).map {
            SliceInput(id: $0.coinGeckoId ?? $0.assetId.uuidString, label: $0.symbol, value: $0.value)
        }

        let otherValue = aggregates.dropFirst(visibleCount).reduce(Decimal.zero) { $0 + $1.value }
        if otherValue > 0 {
            sliceInputs.append(SliceInput(id: "other", label: "other", value: otherValue))
        }

        return makeSlices(from: sliceInputs)
    }

    static func categorySlices(
        from tokens: [TokenEntry],
        prices: [String: Decimal],
        limit: Int = 6) -> [OverviewAssetSlice] {
        var values: [AssetCategory: Decimal] = [:]
        for token in tokens where token.role.isPositive {
            values[token.category, default: 0] += resolvedValue(for: token, prices: prices)
        }

        let sortedValues = values
            .filter { $0.value > 0 }
            .sorted {
                if $0.value == $1.value {
                    return $0.key.rawValue < $1.key.rawValue
                }
                return $0.value > $1.value
            }

        let visibleCount = max(limit, 0)
        var inputs = sortedValues
            .prefix(max(limit, 0))
            .map { category, value in
                SliceInput(id: category.rawValue, label: category.rawValue.capitalized, value: value)
            }

        let otherValue = sortedValues.dropFirst(visibleCount).reduce(Decimal.zero) { $0 + $1.value }
        if otherValue > 0 {
            inputs.append(SliceInput(id: "other", label: "other", value: otherValue))
        }

        return makeSlices(from: inputs)
    }

    static func assetCandidatesByCoinGeckoId(
        from assets: [OverviewAssetCandidate]) -> [String: OverviewAssetCandidate] {
        var candidates: [String: OverviewAssetCandidate] = [:]

        for asset in assets {
            let coinGeckoId = OverviewWatchlistStore.normalize(asset.coinGeckoId)
            guard !coinGeckoId.isEmpty else { continue }

            if let existing = candidates[coinGeckoId] {
                candidates[coinGeckoId] = preferredAssetCandidate(asset, over: existing) ? asset : existing
            } else {
                candidates[coinGeckoId] = asset
            }
        }

        return candidates
    }

    static func priceRows(
        tokens: [TokenEntry],
        assets: [OverviewAssetCandidate],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        watchlistIDs: [String],
        portfolioLimit: Int = 10) -> [OverviewPriceRowData] {
        priceRows(
            tokens: tokens,
            assetsByCoinGeckoId: assetCandidatesByCoinGeckoId(from: assets),
            prices: prices,
            changes24h: changes24h,
            watchlistIDs: watchlistIDs,
            portfolioLimit: portfolioLimit)
    }

    static func priceRows(
        tokens: [TokenEntry],
        assetsByCoinGeckoId: [String: OverviewAssetCandidate],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        watchlistIDs: [String],
        portfolioLimit: Int = 10) -> [OverviewPriceRowData] {
        let watchlist = OverviewWatchlistStore.normalizedUniqueIDs(watchlistIDs)
        let watchlistSet = Set(watchlist)

        var rows: [OverviewPriceRowData] = []
        var seen: Set<String> = []

        for aggregate in sortedAssetAggregates(from: tokens, prices: prices).prefix(max(portfolioLimit, 0)) {
            let rowID = aggregate.coinGeckoId?.lowercased() ?? aggregate.assetId.uuidString
            guard !seen.contains(rowID) else {
                continue
            }
            seen.insert(rowID)
            let coinGeckoId = aggregate.coinGeckoId?.lowercased()
            rows.append(OverviewPriceRowData(
                id: rowID,
                assetId: aggregate.assetId,
                symbol: aggregate.symbol,
                name: aggregate.name,
                coinGeckoId: coinGeckoId,
                price: coinGeckoId.flatMap { prices[$0] } ?? aggregate.fallbackPrice,
                change24h: coinGeckoId.flatMap { changes24h[$0] },
                isWatchlisted: coinGeckoId.map { watchlistSet.contains($0) } ?? false))
        }

        for coinGeckoId in watchlist where !seen.contains(coinGeckoId) {
            guard let asset = assetsByCoinGeckoId[coinGeckoId] else { continue }
            seen.insert(coinGeckoId)
            rows.append(OverviewPriceRowData(
                id: coinGeckoId,
                assetId: asset.id,
                symbol: asset.symbol,
                name: asset.name,
                coinGeckoId: coinGeckoId,
                price: prices[coinGeckoId],
                change24h: changes24h[coinGeckoId],
                isWatchlisted: true))
        }

        return rows
    }

    static func pricePollingIDs(
        tokens: [TokenEntry],
        watchlistIDs: [String]) -> [String] {
        var ids = tokens.compactMap { token -> String? in
            guard token.role.isPositive, token.amount > 0 else { return nil }
            return token.coinGeckoId
        }

        ids.append(contentsOf: watchlistIDs)
        return OverviewWatchlistStore.normalizedUniqueIDs(ids).sorted()
    }

    private struct SliceInput {
        let id: String
        let label: String
        let value: Decimal
    }

    private static func makeSlices(from inputs: [SliceInput]) -> [OverviewAssetSlice] {
        let percentages = displayPercentages(for: inputs.map(\.value))
        return zip(inputs.indices, inputs).map { index, input in
            OverviewAssetSlice(
                id: input.id,
                label: input.label,
                value: input.value,
                displayPercent: percentages[index],
                colorIndex: index)
        }
    }

    private static func sortedAssetAggregates(
        from tokens: [TokenEntry],
        prices: [String: Decimal]) -> [AssetAggregate] {
        var aggregates: [UUID: AssetAggregate] = [:]

        for token in tokens where token.role.isPositive {
            var aggregate = aggregates[token.assetId] ?? AssetAggregate(
                assetId: token.assetId,
                symbol: token.symbol,
                name: token.name,
                category: token.category,
                coinGeckoId: token.coinGeckoId,
                value: 0,
                amount: 0)
            aggregate.coinGeckoId = aggregate.coinGeckoId ?? token.coinGeckoId
            aggregate.value += resolvedValue(for: token, prices: prices)
            if token.amount > 0 {
                aggregate.amount += token.amount
            }
            aggregates[token.assetId] = aggregate
        }

        return aggregates.values
            .filter { $0.value > 0 }
            .sorted {
                if $0.value == $1.value {
                    return $0.symbol.localizedStandardCompare($1.symbol) == .orderedAscending
                }
                return $0.value > $1.value
            }
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
        prices: [String: Decimal]) -> Decimal {
        if let coinGeckoId = token.coinGeckoId?.lowercased(), let price = prices[coinGeckoId] {
            return token.amount * price
        }
        return token.usdValue
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
