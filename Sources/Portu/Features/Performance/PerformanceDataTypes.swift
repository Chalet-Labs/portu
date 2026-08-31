import Foundation
import PortuCore

// swiftformat:disable redundantSendable

// MARK: - Request

/// Everything the Performance data load needs, captured as values so the fetch can run
/// off the main actor. Deliberately excludes anything derived from live SwiftData models.
struct PerformanceDataRequest: Equatable, Sendable {
    var accountId: UUID?
    var startDate: Date
    var chartMode: PerformanceChartMode = .value
    var analyticsScopeFingerprint: String?
    var displayCurrency: FiatCurrency = .usd
    var currentUSDToDisplayRate: Decimal = 1
    var liveDisplayPrices: [String: Decimal] = [:]
    var historicalDisplayPrices: [String: Decimal] = [:]
    var minimumDashboardValue: Decimal = TokenDashboardSettings.defaultMinimumDashboardValue
    var hideUnpriced: Bool = true
    var hideDust: Bool = true
    var historicalBackfillEnabled: Bool = HistoricalPriceBackfillSettings.defaultIsEnabled

    var dashboardSettings: TokenDashboardSettings {
        TokenDashboardSettings(
            minimumDashboardValue: minimumDashboardValue,
            hideUnpriced: hideUnpriced,
            hideDust: hideDust)
    }
}

// MARK: - Value chart

/// One rendered point of the merged provider/local portfolio value series, already
/// converted into the display currency.
struct PerformanceValueChartPoint: Equatable, Sendable {
    var date: Date
    var value: Decimal
    var isPartial: Bool
    var source: PortfolioHistorySource
}

/// Fully shaped value-chart payload. `estimatedPoints` is already currency-converted and
/// already filtered through `ProviderPortfolioHistory.estimatesOutsideProviderCoverage`,
/// so the view renders it verbatim.
struct PerformanceValueChartData: Equatable, Sendable {
    var points: [PerformanceValueChartPoint] = []
    var estimatedPoints: [HistoricalPortfolioValuePoint] = []
    var providerDisclosure: String?
    var historicalFXUnavailableBefore: Date?
    /// Retained (pre-conversion) provider points existed. Together with
    /// `hasConvertedProviderPoints == false` this is the historical-FX-unavailable condition.
    var hasRetainedProviderPoints: Bool = false
    var hasConvertedProviderPoints: Bool = false

    static let empty = Self()
}

// MARK: - Bottom panel

/// Always-visible bottom panel payload. `priceChanges` arrives sorted by absolute percent
/// change (descending, name tie-break) and already limited to the rendered top five.
struct PerformanceBottomPanelData: Equatable, Sendable {
    var categoryChanges: [CategoryChange] = []
    var priceChanges: [AssetPricePeriodChange] = []

    static let empty = Self()
}

// MARK: - Category chart source

/// One category candidate for a single (UTC day, account, asset) group. `convertedValue`
/// is pre-converted into the display currency using the candidate's own timestamp.
struct PerformanceCategoryChartCandidate: Equatable, Sendable {
    var timestamp: Date
    var categoryID: String
    var categoryName: String
    var convertedValue: Decimal
}

/// Compact stand-in for the raw `AssetSnapshot` rows of one dedup group. Holding the latest
/// candidate per category — rather than the single overall latest — is what lets a category
/// toggle be reprojected without touching SwiftData: disabling the winning category must
/// promote the next-latest surviving candidate, exactly as the legacy filter-then-dedup did.
///
/// `candidates` is ordered by the encounter index of each category's retained row, which is
/// what reproduces the legacy equal-timestamp "first row wins" tie-break.
struct PerformanceCategoryChartSourceGroup: Equatable, Sendable {
    var day: Date
    var accountId: UUID
    var assetId: UUID
    var candidates: [PerformanceCategoryChartCandidate]
}

enum PerformanceCategoryChartProjection {
    /// Convert raw snapshot entries into the compact per-group source.
    ///
    /// Retention rule per (group, category): highest timestamp wins; on equal timestamps the
    /// earlier entry wins — identical to `deduplicateByDayAndAsset`'s
    /// `existing.timestamp >= entry.timestamp { continue }`.
    static func source(
        entries: [CategorySnapshotEntry],
        conversionContext: CurrencyConversionContext = .usd) -> [PerformanceCategoryChartSourceGroup] {
        struct GroupKey: Hashable {
            let day: Date
            let accountId: UUID
            let assetId: UUID
        }
        struct Retained {
            var index: Int
            var candidate: PerformanceCategoryChartCandidate
        }

        var order: [GroupKey] = []
        var retained: [GroupKey: [String: Retained]] = [:]

        for (index, entry) in entries.enumerated() {
            let key = GroupKey(
                day: HistoricalPriceCalendar.utcStartOfDay(for: entry.timestamp),
                accountId: entry.accountId,
                assetId: entry.assetId)
            if retained[key] == nil {
                order.append(key)
                retained[key] = [:]
            }
            if let existing = retained[key]?[entry.categoryID], existing.candidate.timestamp >= entry.timestamp {
                continue
            }
            retained[key]?[entry.categoryID] = Retained(
                index: index,
                candidate: PerformanceCategoryChartCandidate(
                    timestamp: entry.timestamp,
                    categoryID: entry.categoryID,
                    categoryName: entry.categoryName,
                    convertedValue: conversionContext.convertUSDValue(entry.usdValue, on: entry.timestamp)))
        }

        return order.map { key in
            PerformanceCategoryChartSourceGroup(
                day: key.day,
                accountId: key.accountId,
                assetId: key.assetId,
                candidates: retained[key, default: [:]].values
                    .sorted { $0.index < $1.index }
                    .map(\.candidate))
        }
    }

    /// Select the latest enabled candidate per group and aggregate per (day, category).
    ///
    /// Output equals the legacy `aggregateCategorySnapshots(entries: entries.filter { enabled })`
    /// for every disabled set: the winner scan mirrors the legacy dedup tie-break, and the
    /// sort is the legacy comparator.
    static func points(
        source: [PerformanceCategoryChartSourceGroup],
        disabledCategoryIDs: Set<String>) -> [CategoryChartPoint] {
        var grouped: [Date: [String: (name: String, value: Decimal)]] = [:]

        for group in source {
            var winner: PerformanceCategoryChartCandidate?
            for candidate in group.candidates where !disabledCategoryIDs.contains(candidate.categoryID) {
                if let current = winner, current.timestamp >= candidate.timestamp {
                    continue
                }
                winner = candidate
            }
            guard let winner else { continue }
            var category = grouped[group.day, default: [:]][winner.categoryID] ?? (winner.categoryName, 0)
            category.value += winner.convertedValue
            grouped[group.day, default: [:]][winner.categoryID] = category
        }

        return grouped.flatMap { date, categories in
            categories.map {
                CategoryChartPoint(
                    date: date,
                    categoryID: $0.key,
                    categoryName: $0.value.name,
                    value: $0.value.value)
            }
        }
        .sorted {
            if $0.date != $1.date {
                return $0.date < $1.date
            }
            let nameOrder = $0.categoryName.localizedStandardCompare($1.categoryName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return $0.categoryID < $1.categoryID
        }
    }
}

// MARK: - Snapshot

/// The complete off-main load result. Only value types — no persistent model reaches state.
struct PerformanceDataSnapshot: Equatable, Sendable {
    /// Full ordered category list (resolver order), including categories with no data, so the
    /// toggle buttons stay stable and the `.defaults` fallback still renders.
    var categories: [PortfolioCategorySnapshot] = []
    var categoryChartSource: [PerformanceCategoryChartSourceGroup] = []
    var valueChart: PerformanceValueChartData = .empty
    var bottomPanel: PerformanceBottomPanelData = .empty

    static let empty = Self()
}

// MARK: - Row projections

/// Value projection of one `AssetSnapshot` row. Rows are converted at the fetch boundary so
/// every aggregation step below operates on values only: no persistent model escapes the
/// fetcher, and no lazily-faulted property is ever read off the actor.
struct PerformanceSnapshotRow: Equatable, Sendable {
    var accountId: UUID
    var assetId: UUID
    var timestamp: Date
    var symbol: String
    var category: AssetCategory
    var amount: Decimal
    var usdValue: Decimal
    var borrowAmount: Decimal
    var borrowUsdValue: Decimal
}

/// Value projection of one `Asset` row, carrying the pre-normalized onchain identity.
struct PerformanceAssetRow: Equatable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
    var coinGeckoId: String?
    var identity: OnchainTokenIdentity?

    /// Name precedence used by the price-change panel: trimmed name, then trimmed symbol.
    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSymbol.isEmpty ? "Unknown asset" : trimmedSymbol
    }
}

// MARK: - Pure shaping

/// Aggregation that used to live in `AssetsChartMode`, `ValueChartMode` and
/// `PerformanceBottomPanel` computed properties. Pure value-in/value-out, so it is
/// exercisable without a `ModelContainer` and callable from any isolation.
enum PerformanceDataShaping {
    static let priceChangeLimit = 5

    /// Reproduces the former `CategorySnapshotEntry(snapshot:categoryResolver:)` main-actor
    /// convenience initializer against value rows. The SQL lower bound is the UTC day start,
    /// so the exact `startDate` boundary is re-applied here just as the view body did.
    static func categoryEntries(
        rows: [PerformanceSnapshotRow],
        from startDate: Date,
        visibleAssetIDs: Set<UUID>? = nil,
        resolver: PortfolioCategoryResolver) -> [CategorySnapshotEntry] {
        rows.compactMap { row in
            guard row.timestamp >= startDate else { return nil }
            if let visibleAssetIDs, !visibleAssetIDs.contains(row.assetId) {
                return nil
            }
            let resolved = resolver.resolve(symbol: row.symbol, legacyCategory: row.category)
            return CategorySnapshotEntry(
                accountId: row.accountId,
                assetId: row.assetId,
                timestamp: row.timestamp,
                category: row.category,
                categoryID: resolved.id.uuidString,
                categoryName: resolved.name,
                usdValue: row.usdValue)
        }
    }

    static func estimateEntries(
        rows: [PerformanceSnapshotRow],
        overrides: [TokenPricingOverrideSnapshot],
        assets: [PerformanceAssetRow]) -> [HistoricalEstimateSnapshotEntry] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(overrides)
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        return rows.map { row in
            let asset = assetsById[row.assetId]
            return HistoricalEstimateSnapshotEntry(
                accountId: row.accountId,
                assetId: row.assetId,
                timestamp: row.timestamp,
                coinGeckoId: asset?.coinGeckoId,
                coinGeckoIdOverride: overridesByAssetId[row.assetId]?.coinGeckoIdOverride,
                onchainIdentity: asset?.identity,
                amount: row.amount,
                borrowAmount: row.borrowAmount,
                netUSDValue: row.usdValue - row.borrowUsdValue)
        }
    }

    /// Merged series -> rendered points. Provider points only survive when the currency
    /// conversion produced a value for their timestamp, matching the former view body.
    static func valueChartPoints(
        merged: [PortfolioHistoryPoint],
        converted: [ConvertedProviderPortfolioValuePoint],
        conversion: CurrencyConversionContext) -> [PerformanceValueChartPoint] {
        let convertedByTimestamp = Dictionary(
            uniqueKeysWithValues: converted.map { ($0.timestamp, $0.value) })
        return merged.compactMap { point in
            switch point.source {
            case .local:
                PerformanceValueChartPoint(
                    date: point.timestamp,
                    value: conversion.convertUSDValue(point.usdValue, on: point.timestamp),
                    isPartial: !point.isReliable,
                    source: point.source)
            case .zerion:
                convertedByTimestamp[point.timestamp].map {
                    PerformanceValueChartPoint(
                        date: point.timestamp,
                        value: $0,
                        isPartial: false,
                        source: point.source)
                }
            }
        }
    }

    /// Rendering order of the price-change column: absolute percent change descending, then
    /// display name — capped at the five rows the panel shows.
    static func orderedPriceChanges(
        _ changes: [AssetPricePeriodChange],
        limit: Int = priceChangeLimit) -> [AssetPricePeriodChange] {
        Array(
            changes
                .sorted {
                    let lhs = absolute($0.percentChange)
                    let rhs = absolute($1.percentChange)
                    if lhs != rhs {
                        return lhs > rhs
                    }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .prefix(limit))
    }

    /// Display name per historical-price ID. Assets are visited in display-name order and the
    /// first name recorded for an ID wins, so precedence between an override id, the asset's
    /// own CoinGecko id, native/known-contract ids and mapped ids is preserved.
    static func assetNames(
        assets: [PerformanceAssetRow],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot]) -> [String: String] {
        let overridesByAssetId = TokenSettingsFeature.overridesByAssetId(overrides)
        let mappingsByIdentity = TokenIdentityMappingFeature.mappingsByIdentity(mappings)
        var names: [String: String] = [:]

        for asset in assets.sorted(by: sortAssetNames) {
            let name = asset.displayName
            let identity = asset.identity

            record(name, for: overridesByAssetId[asset.id]?.coinGeckoIdOverride, in: &names)
            record(name, for: asset.coinGeckoId, in: &names)
            record(name, for: TokenIdentityMappingFeature.nativeCoinGeckoID(for: identity), in: &names)
            record(name, for: TokenIdentityMappingFeature.knownContractCoinGeckoID(for: identity), in: &names)
            record(name, for: identity?.historicalPriceID, in: &names)

            if let identity, let mapping = mappingsByIdentity[identity] {
                record(name, for: mapping.coinGeckoId, in: &names)
                record(name, for: mapping.zapperId, in: &names)
            }
        }

        return names
    }

    private static func sortAssetNames(_ lhs: PerformanceAssetRow, _ rhs: PerformanceAssetRow) -> Bool {
        let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func record(_ name: String, for id: String?, in names: inout [String: String]) {
        guard let normalizedID = TokenIdentityMappingFeature.normalizedHistoricalPriceID(id) else { return }
        names[normalizedID] = names[normalizedID] ?? name
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
