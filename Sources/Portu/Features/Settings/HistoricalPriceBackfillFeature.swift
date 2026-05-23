// swiftlint:disable file_length

import ComposableArchitecture
import Foundation
import PortuCore
import SwiftData

struct HistoricalBackfillCandidate: Equatable, Identifiable {
    var id: String {
        historicalPriceID
    }

    var coinGeckoId: String {
        historicalPriceID
    }

    let historicalPriceID: String
    let source: HistoricalBackfillPriceSource
    let assetIds: [UUID]
}

enum HistoricalBackfillPriceSource: Equatable {
    case coingecko(String)
    case zapper(OnchainTokenIdentity)
}

struct HistoricalBackfillSnapshotEntry: Equatable {
    let assetId: UUID
    let coinGeckoId: String?
    let onchainIdentity: OnchainTokenIdentity?
    let amount: Decimal
    let borrowAmount: Decimal
    let usdValue: Decimal
    let borrowUsdValue: Decimal
}

private struct HistoricalBackfillAssetReference {
    let assetId: UUID
    let coinGeckoId: String?
    let onchainIdentity: OnchainTokenIdentity?
    let override: TokenPricingOverrideSnapshot?
}

struct HistoricalBackfillWriteResult: Equatable {
    var inserted: Int
    var updated: Int
}

struct HistoricalBackfillResult: Equatable {
    var requestedAssets: Int
    var fetchedAssets: Int
    var skippedAssets: Int
    var insertedPoints: Int
    var updatedPoints: Int
    var failedCoinGeckoIDs: [String]
}

enum HistoricalBackfillStatus: Equatable {
    case idle
    case running
    case clearing
    case succeeded(HistoricalBackfillResult)
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .running, .clearing:
            true
        case .idle, .succeeded, .failed:
            false
        }
    }
}

struct HistoricalBackfillError: LocalizedError, Equatable {
    /// Discriminator for failure category — lets the UI offer category-appropriate
    /// guidance (configure key vs retry vs unlock keychain) instead of just an
    /// opaque message.
    enum Kind: Equatable {
        /// CoinGecko/Zapper returned 429 and the runner exhausted its retry.
        case rateLimited
        /// Provider rejected our credentials (or none were configured).
        case unauthorized(provider: String)
        /// Backfill couldn't be started because nothing was fetchable — for example
        /// every candidate is onchain but no Zapper key is configured.
        case preflightUnavailable
        /// Uncategorized failure; the message is the only signal.
        case other
    }

    let message: String
    let kind: Kind

    init(message: String, kind: Kind = .other) {
        self.message = message
        self.kind = kind
    }

    var errorDescription: String? {
        message
    }
}

enum HistoricalBackfillCandidateResolver {
    static func candidates(
        tokens: [TokenEntry],
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot] = [],
        prices: [String: Decimal] = [:],
        dashboardSettings: TokenDashboardSettings = .defaults,
        resolvedCoinGeckoIDs: [OnchainTokenIdentity: String] = [:]) -> [HistoricalBackfillCandidate] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        let mappingMap = TokenIdentityMappingFeature.mappingsByIdentity(mappings)
        var grouped: [HistoricalBackfillCandidateKey: Set<UUID>] = [:]
        for token in tokens where shouldIncludeToken(
            token,
            override: overrideMap[token.assetId],
            prices: prices,
            dashboardSettings: dashboardSettings) {
            addCandidate(
                asset: HistoricalBackfillAssetReference(
                    assetId: token.assetId,
                    coinGeckoId: token.coinGeckoId,
                    onchainIdentity: token.onchainIdentity,
                    override: overrideMap[token.assetId]),
                mappingsByIdentity: mappingMap,
                resolvedCoinGeckoIDs: resolvedCoinGeckoIDs,
                grouped: &grouped)
        }
        for snapshot in snapshots where shouldIncludeSnapshot(
            snapshot,
            override: overrideMap[snapshot.assetId],
            dashboardSettings: dashboardSettings) {
            addCandidate(
                asset: HistoricalBackfillAssetReference(
                    assetId: snapshot.assetId,
                    coinGeckoId: snapshot.coinGeckoId,
                    onchainIdentity: snapshot.onchainIdentity,
                    override: overrideMap[snapshot.assetId]),
                mappingsByIdentity: mappingMap,
                resolvedCoinGeckoIDs: resolvedCoinGeckoIDs,
                grouped: &grouped)
        }
        return grouped
            .map { candidateKey, ids in
                HistoricalBackfillCandidate(
                    historicalPriceID: candidateKey.historicalPriceID,
                    source: candidateKey.source,
                    assetIds: ids.sorted { $0.uuidString < $1.uuidString })
            }
            .sorted { $0.historicalPriceID < $1.historicalPriceID }
    }

    static func sourceAssetIDs(
        tokens: [TokenEntry],
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        overrides: [TokenPricingOverrideSnapshot] = [],
        prices: [String: Decimal] = [:],
        dashboardSettings: TokenDashboardSettings = .defaults) -> Set<UUID> {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        let tokenIDs = tokens.compactMap { token -> UUID? in
            guard
                shouldIncludeToken(
                    token,
                    override: overrideMap[token.assetId],
                    prices: prices,
                    dashboardSettings: dashboardSettings)
            else { return nil }
            return token.assetId
        }
        let snapshotIDs = snapshots.compactMap { snapshot -> UUID? in
            guard
                shouldIncludeSnapshot(
                    snapshot,
                    override: overrideMap[snapshot.assetId],
                    dashboardSettings: dashboardSettings)
            else { return nil }
            return snapshot.assetId
        }
        return Set(tokenIDs + snapshotIDs)
    }

    static func onchainIdentitiesNeedingResolution(
        tokens: [TokenEntry],
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot] = [],
        prices: [String: Decimal] = [:],
        dashboardSettings: TokenDashboardSettings = .defaults) -> [OnchainTokenIdentity] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        let mappingMap = TokenIdentityMappingFeature.mappingsByIdentity(mappings)
        var identities = Set<OnchainTokenIdentity>()
        for token in tokens where shouldIncludeToken(
            token,
            override: overrideMap[token.assetId],
            prices: prices,
            dashboardSettings: dashboardSettings) {
            addUnresolvedIdentity(
                assetId: token.assetId,
                coinGeckoId: token.coinGeckoId,
                onchainIdentity: token.onchainIdentity,
                override: overrideMap[token.assetId],
                mappingsByIdentity: mappingMap,
                identities: &identities)
        }
        for snapshot in snapshots where shouldIncludeSnapshot(
            snapshot,
            override: overrideMap[snapshot.assetId],
            dashboardSettings: dashboardSettings) {
            addUnresolvedIdentity(
                assetId: snapshot.assetId,
                coinGeckoId: snapshot.coinGeckoId,
                onchainIdentity: snapshot.onchainIdentity,
                override: overrideMap[snapshot.assetId],
                mappingsByIdentity: mappingMap,
                identities: &identities)
        }
        return identities.sorted {
            if $0.chain.rawValue != $1.chain.rawValue { return $0.chain.rawValue < $1.chain.rawValue }
            return $0.contractAddress < $1.contractAddress
        }
    }

    static func assetIDsByOnchainIdentity(
        tokens: [TokenEntry],
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        overrides: [TokenPricingOverrideSnapshot],
        prices: [String: Decimal] = [:],
        dashboardSettings: TokenDashboardSettings = .defaults) -> [OnchainTokenIdentity: Set<UUID>] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var result: [OnchainTokenIdentity: Set<UUID>] = [:]
        for token in tokens where shouldIncludeToken(
            token,
            override: overrideMap[token.assetId],
            prices: prices,
            dashboardSettings: dashboardSettings) {
            addUnresolvedAsset(
                assetId: token.assetId,
                coinGeckoId: token.coinGeckoId,
                onchainIdentity: token.onchainIdentity,
                override: overrideMap[token.assetId],
                result: &result)
        }
        for snapshot in snapshots where shouldIncludeSnapshot(
            snapshot,
            override: overrideMap[snapshot.assetId],
            dashboardSettings: dashboardSettings) {
            addUnresolvedAsset(
                assetId: snapshot.assetId,
                coinGeckoId: snapshot.coinGeckoId,
                onchainIdentity: snapshot.onchainIdentity,
                override: overrideMap[snapshot.assetId],
                result: &result)
        }
        return result
    }

    private static func shouldIncludeToken(
        _ token: TokenEntry,
        override: TokenPricingOverrideSnapshot?,
        prices: [String: Decimal],
        dashboardSettings: TokenDashboardSettings) -> Bool {
        guard token.amount > 0 else { return false }
        guard token.role.isPositive || token.role.isBorrow else { return false }
        guard override?.isIgnored != true else { return false }
        if override?.alwaysShow == true { return true }

        let value = TokenSettingsFeature.resolvedValue(
            token: token,
            prices: prices,
            override: override) ?? token.usdValue
        if value == 0 {
            return !dashboardSettings.hideUnpriced
        }
        if absolute(value) < normalizedThreshold(dashboardSettings.minimumDashboardValue) {
            return !dashboardSettings.hideDust
        }
        return true
    }

    private static func shouldIncludeSnapshot(
        _ snapshot: HistoricalBackfillSnapshotEntry,
        override: TokenPricingOverrideSnapshot?,
        dashboardSettings: TokenDashboardSettings) -> Bool {
        let netAmount = snapshot.amount - snapshot.borrowAmount
        guard netAmount != 0 else { return false }
        guard override?.isIgnored != true else { return false }
        if override?.alwaysShow == true { return true }

        let netValue = snapshotValue(snapshot, override: override)
        if netValue == 0 {
            return !dashboardSettings.hideUnpriced
        }
        if absolute(netValue) < normalizedThreshold(dashboardSettings.minimumDashboardValue) {
            return !dashboardSettings.hideDust
        }
        return true
    }

    private static func snapshotValue(
        _ snapshot: HistoricalBackfillSnapshotEntry,
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        if let manualPrice = override?.manualPriceUSD, manualPrice > 0 {
            return (snapshot.amount - snapshot.borrowAmount) * manualPrice
        }
        return snapshot.usdValue - snapshot.borrowUsdValue
    }

    private static func addCandidate(
        asset: HistoricalBackfillAssetReference,
        mappingsByIdentity: [OnchainTokenIdentity: TokenIdentityMappingSnapshot],
        resolvedCoinGeckoIDs: [OnchainTokenIdentity: String],
        grouped: inout [HistoricalBackfillCandidateKey: Set<UUID>]) {
        if asset.override?.manualPriceUSD != nil, normalizedID(asset.override?.coinGeckoIdOverride) == nil {
            return
        }

        let explicitCoinGeckoID = normalizedID(asset.override?.coinGeckoIdOverride)
            ?? normalizedID(asset.coinGeckoId)
        guard let onchainIdentity = asset.onchainIdentity else {
            if let explicitCoinGeckoID {
                grouped[
                    HistoricalBackfillCandidateKey(
                        historicalPriceID: explicitCoinGeckoID,
                        source: .coingecko(explicitCoinGeckoID)),
                    default: []
                ].insert(asset.assetId)
            }
            return
        }

        if let nativeID = TokenIdentityMappingFeature.nativeCoinGeckoID(for: onchainIdentity) {
            grouped[
                HistoricalBackfillCandidateKey(
                    historicalPriceID: nativeID,
                    source: .coingecko(nativeID)),
                default: []
            ].insert(asset.assetId)
            return
        }

        let providerCoinGeckoID = explicitCoinGeckoID
            ?? TokenIdentityMappingFeature.mappedCoinGeckoID(
                for: onchainIdentity,
                mappingsByIdentity: mappingsByIdentity)
            ?? normalizedID(resolvedCoinGeckoIDs[onchainIdentity])
            ?? TokenIdentityMappingFeature.knownContractCoinGeckoID(for: onchainIdentity)
        if let providerCoinGeckoID {
            let cacheKey = TokenIdentityMappingFeature.priceID(
                coinGeckoId: providerCoinGeckoID,
                onchainIdentity: onchainIdentity) ?? onchainIdentity.historicalPriceID
            grouped[
                HistoricalBackfillCandidateKey(
                    historicalPriceID: cacheKey,
                    source: .coingecko(providerCoinGeckoID)),
                default: []
            ].insert(asset.assetId)
        } else {
            grouped[
                HistoricalBackfillCandidateKey(
                    historicalPriceID: onchainIdentity.historicalPriceID,
                    source: .zapper(onchainIdentity)),
                default: []
            ].insert(asset.assetId)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func addUnresolvedIdentity(
        assetId _: UUID,
        coinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity?,
        override: TokenPricingOverrideSnapshot?,
        mappingsByIdentity: [OnchainTokenIdentity: TokenIdentityMappingSnapshot],
        identities: inout Set<OnchainTokenIdentity>) {
        guard shouldResolveOnchain(coinGeckoId: coinGeckoId, override: override), let onchainIdentity else {
            return
        }
        guard
            TokenIdentityMappingFeature.nativeCoinGeckoID(for: onchainIdentity) == nil
        else {
            return
        }
        guard
            TokenIdentityMappingFeature.mappedCoinGeckoID(
                for: onchainIdentity,
                mappingsByIdentity: mappingsByIdentity) == nil
        else {
            return
        }
        identities.insert(onchainIdentity)
    }

    private static func addUnresolvedAsset(
        assetId: UUID,
        coinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity?,
        override: TokenPricingOverrideSnapshot?,
        result: inout [OnchainTokenIdentity: Set<UUID>]) {
        guard shouldResolveOnchain(coinGeckoId: coinGeckoId, override: override), let onchainIdentity else {
            return
        }
        guard
            TokenIdentityMappingFeature.nativeCoinGeckoID(for: onchainIdentity) == nil
        else {
            return
        }
        result[onchainIdentity, default: []].insert(assetId)
    }

    private static func shouldResolveOnchain(
        coinGeckoId: String?,
        override: TokenPricingOverrideSnapshot?) -> Bool {
        if override?.manualPriceUSD != nil, normalizedID(override?.coinGeckoIdOverride) == nil {
            return false
        }
        return normalizedID(override?.coinGeckoIdOverride) == nil && normalizedID(coinGeckoId) == nil
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedThreshold(_ value: Decimal) -> Decimal {
        value < 0 ? 0 : value
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}

private struct HistoricalBackfillCandidateKey: Hashable {
    let historicalPriceID: String
    let source: HistoricalBackfillPriceSource

    init(historicalPriceID: String, source: HistoricalBackfillPriceSource) {
        self.historicalPriceID = historicalPriceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.source = source
    }
}

extension HistoricalBackfillPriceSource: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .coingecko(id):
            hasher.combine("coingecko")
            hasher.combine(id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        case let .zapper(identity):
            hasher.combine("zapper")
            hasher.combine(identity)
        }
    }
}

enum HistoricalPriceCacheWriter {
    @MainActor
    static func upsert(
        _ dtos: [HistoricalPriceDTO],
        in context: ModelContext,
        fetchedAt: Date = .now) throws -> HistoricalBackfillWriteResult {
        guard dtos.isEmpty == false else {
            return HistoricalBackfillWriteResult(inserted: 0, updated: 0)
        }

        let incomingKeys = dtos.map {
            HistoricalPriceCacheKey(coinGeckoId: $0.coinGeckoId, day: $0.day)
        }
        let daysByCoinGeckoID = Dictionary(grouping: incomingKeys, by: \.coinGeckoId)
            .mapValues { Array(Set($0.map(\.day))) }
        var existing: [HistoricalPricePoint] = []
        // Scope per coinGeckoId so we never fetch (token A day, token B day) cross-matches.
        for (coinGeckoID, daysForID) in daysByCoinGeckoID {
            let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>(
                predicate: #Predicate { row in
                    row.coinGeckoId == coinGeckoID && daysForID.contains(row.day)
                }))
            existing.append(contentsOf: rows)
        }
        do {
            // SwiftData only enforces id uniqueness for this model; cache uniqueness
            // for (coinGeckoId, day) is enforced here by scoped upsert and dedupe.
            let groupedExisting = Dictionary(grouping: existing) {
                HistoricalPriceCacheKey(coinGeckoId: $0.coinGeckoId, day: $0.day)
            }
            var existingByKey: [HistoricalPriceCacheKey: HistoricalPricePoint] = [:]
            for (cacheKey, rows) in groupedExisting {
                let sortedRows = rows.sorted { lhs, rhs in
                    if lhs.fetchedAt == rhs.fetchedAt {
                        lhs.id.uuidString < rhs.id.uuidString
                    } else {
                        lhs.fetchedAt > rhs.fetchedAt
                    }
                }
                guard let survivor = sortedRows.first else { continue }
                existingByKey[cacheKey] = survivor
                for duplicate in sortedRows.dropFirst() {
                    context.delete(duplicate)
                }
            }
            var inserted = 0
            var updated = 0

            for dto in dtos {
                let cacheKey = HistoricalPriceCacheKey(coinGeckoId: dto.coinGeckoId, day: dto.day)
                if let row = existingByKey[cacheKey] {
                    row.usdPrice = dto.usdPrice
                    row.source = dto.source
                    row.fetchedAt = fetchedAt
                    updated += 1
                } else {
                    let row = HistoricalPricePoint(dto: dto, fetchedAt: fetchedAt)
                    context.insert(row)
                    existingByKey[cacheKey] = row
                    inserted += 1
                }
            }

            try context.save()
            return HistoricalBackfillWriteResult(inserted: inserted, updated: updated)
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    static func clear(in context: ModelContext) throws {
        do {
            try context.delete(model: HistoricalPricePoint.self)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

private struct HistoricalPriceCacheKey: Hashable {
    let coinGeckoId: String
    let day: Date

    init(coinGeckoId: String, day: Date) {
        self.coinGeckoId = coinGeckoId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
    }
}

@Reducer
struct HistoricalPriceBackfillFeature {
    @ObservableState
    struct State: Equatable {
        var status: HistoricalBackfillStatus = .idle
    }

    enum Action: Equatable {
        case backfillButtonTapped
        case backfillCompleted(Result<HistoricalBackfillResult, HistoricalBackfillError>)
        case clearCacheButtonTapped
        case clearCacheCompleted(Result<Void, HistoricalBackfillError>)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.backfillButtonTapped, .backfillButtonTapped):
                true
            case let (.backfillCompleted(lhsResult), .backfillCompleted(rhsResult)):
                lhsResult == rhsResult
            case (.clearCacheButtonTapped, .clearCacheButtonTapped):
                true
            case (.clearCacheCompleted(.success), .clearCacheCompleted(.success)):
                true
            case let (.clearCacheCompleted(.failure(lhsError)), .clearCacheCompleted(.failure(rhsError))):
                lhsError == rhsError
            default:
                false
            }
        }
    }

    @Dependency(\.historicalPriceBackfill) var historicalPriceBackfill

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .backfillButtonTapped:
                guard !state.status.isRunning else { return .none }
                state.status = .running
                return .run { send in
                    do {
                        let result = try await historicalPriceBackfill.run()
                        await send(.backfillCompleted(.success(result)))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.backfillCompleted(.failure(HistoricalBackfillError(message: error.localizedDescription))))
                    }
                }

            case let .backfillCompleted(.success(result)):
                state.status = .succeeded(result)
                return .none

            case let .backfillCompleted(.failure(error)):
                state.status = .failed(error.message)
                return .none

            case .clearCacheButtonTapped:
                guard !state.status.isRunning else { return .none }
                state.status = .clearing
                return .run { send in
                    do {
                        try await historicalPriceBackfill.clearCache()
                        await send(.clearCacheCompleted(.success(())))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.clearCacheCompleted(.failure(HistoricalBackfillError(message: error.localizedDescription))))
                    }
                }

            case .clearCacheCompleted(.success):
                state.status = .idle
                return .none

            case let .clearCacheCompleted(.failure(error)):
                state.status = .failed(error.message)
                return .none
            }
        }
    }
}
