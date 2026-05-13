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
    let message: String

    var errorDescription: String? {
        message
    }
}

enum HistoricalBackfillCandidateResolver {
    static func candidates(
        tokens: [TokenEntry],
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        overrides: [TokenPricingOverrideSnapshot],
        resolvedCoinGeckoIDs: [OnchainTokenIdentity: String] = [:]) -> [HistoricalBackfillCandidate] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var grouped: [HistoricalBackfillCandidateKey: Set<UUID>] = [:]
        for token in tokens where token.amount > 0 && (token.role.isPositive || token.role.isBorrow) {
            addCandidate(
                asset: HistoricalBackfillAssetReference(
                    assetId: token.assetId,
                    coinGeckoId: token.coinGeckoId,
                    onchainIdentity: token.onchainIdentity,
                    override: overrideMap[token.assetId]),
                resolvedCoinGeckoIDs: resolvedCoinGeckoIDs,
                grouped: &grouped)
        }
        for snapshot in snapshots where snapshot.amount - snapshot.borrowAmount != 0 {
            addCandidate(
                asset: HistoricalBackfillAssetReference(
                    assetId: snapshot.assetId,
                    coinGeckoId: snapshot.coinGeckoId,
                    onchainIdentity: snapshot.onchainIdentity,
                    override: overrideMap[snapshot.assetId]),
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
        snapshots: [HistoricalBackfillSnapshotEntry] = []) -> Set<UUID> {
        let tokenIDs = tokens.compactMap { token -> UUID? in
            guard token.amount > 0, token.role.isPositive || token.role.isBorrow else { return nil }
            return token.assetId
        }
        let snapshotIDs = snapshots.compactMap { snapshot -> UUID? in
            guard snapshot.amount - snapshot.borrowAmount != 0 else { return nil }
            return snapshot.assetId
        }
        return Set(tokenIDs + snapshotIDs)
    }

    static func onchainIdentitiesNeedingResolution(
        tokens: [TokenEntry],
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        overrides: [TokenPricingOverrideSnapshot]) -> [OnchainTokenIdentity] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var identities = Set<OnchainTokenIdentity>()
        for token in tokens where token.amount > 0 && (token.role.isPositive || token.role.isBorrow) {
            addUnresolvedIdentity(
                assetId: token.assetId,
                coinGeckoId: token.coinGeckoId,
                onchainIdentity: token.onchainIdentity,
                override: overrideMap[token.assetId],
                identities: &identities)
        }
        for snapshot in snapshots where snapshot.amount - snapshot.borrowAmount != 0 {
            addUnresolvedIdentity(
                assetId: snapshot.assetId,
                coinGeckoId: snapshot.coinGeckoId,
                onchainIdentity: snapshot.onchainIdentity,
                override: overrideMap[snapshot.assetId],
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
        overrides: [TokenPricingOverrideSnapshot]) -> [OnchainTokenIdentity: Set<UUID>] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var result: [OnchainTokenIdentity: Set<UUID>] = [:]
        for token in tokens where token.amount > 0 && (token.role.isPositive || token.role.isBorrow) {
            addUnresolvedAsset(
                assetId: token.assetId,
                coinGeckoId: token.coinGeckoId,
                onchainIdentity: token.onchainIdentity,
                override: overrideMap[token.assetId],
                result: &result)
        }
        for snapshot in snapshots where snapshot.amount - snapshot.borrowAmount != 0 {
            addUnresolvedAsset(
                assetId: snapshot.assetId,
                coinGeckoId: snapshot.coinGeckoId,
                onchainIdentity: snapshot.onchainIdentity,
                override: overrideMap[snapshot.assetId],
                result: &result)
        }
        return result
    }

    private static func addCandidate(
        asset: HistoricalBackfillAssetReference,
        resolvedCoinGeckoIDs: [OnchainTokenIdentity: String],
        grouped: inout [HistoricalBackfillCandidateKey: Set<UUID>]) {
        if asset.override?.manualPriceUSD != nil, normalizedID(asset.override?.coinGeckoIdOverride) == nil {
            return
        }
        if let resolvedID = normalizedID(asset.override?.coinGeckoIdOverride) ?? normalizedID(asset.coinGeckoId) {
            grouped[HistoricalBackfillCandidateKey(source: .coingecko(resolvedID)), default: []].insert(asset.assetId)
            return
        }
        guard let onchainIdentity = asset.onchainIdentity else { return }
        if let resolvedID = normalizedID(resolvedCoinGeckoIDs[onchainIdentity]) {
            grouped[HistoricalBackfillCandidateKey(source: .coingecko(resolvedID)), default: []].insert(asset.assetId)
        } else {
            grouped[HistoricalBackfillCandidateKey(source: .zapper(onchainIdentity)), default: []].insert(asset.assetId)
        }
    }

    private static func addUnresolvedIdentity(
        assetId _: UUID,
        coinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity?,
        override: TokenPricingOverrideSnapshot?,
        identities: inout Set<OnchainTokenIdentity>) {
        guard shouldResolveOnchain(coinGeckoId: coinGeckoId, override: override), let onchainIdentity else {
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
}

private struct HistoricalBackfillCandidateKey: Hashable {
    let historicalPriceID: String
    let source: HistoricalBackfillPriceSource

    init(source: HistoricalBackfillPriceSource) {
        self.source = source
        switch source {
        case let .coingecko(id):
            self.historicalPriceID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        case let .zapper(identity):
            self.historicalPriceID = identity.historicalPriceID
        }
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
        let coinGeckoIDs = Array(Set(incomingKeys.map(\.coinGeckoId)))
        let days = Array(Set(incomingKeys.map(\.day)))
        let existing = try context.fetch(FetchDescriptor<HistoricalPricePoint>(
            predicate: #Predicate { row in
                coinGeckoIDs.contains(row.coinGeckoId) && days.contains(row.day)
            }))
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
            case let (.clearCacheCompleted(.success), .clearCacheCompleted(.success)):
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
