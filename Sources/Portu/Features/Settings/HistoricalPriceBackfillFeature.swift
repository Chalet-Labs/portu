import ComposableArchitecture
import Foundation
import PortuCore
import SwiftData

struct HistoricalBackfillCandidate: Equatable, Identifiable {
    var id: String {
        coinGeckoId
    }

    let coinGeckoId: String
    let assetIds: [UUID]
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
    case succeeded(HistoricalBackfillResult)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

struct HistoricalBackfillError: Error, Equatable {
    let message: String
}

enum HistoricalBackfillCandidateResolver {
    static func candidates(
        tokens: [TokenEntry],
        overrides: [TokenPricingOverrideSnapshot]) -> [HistoricalBackfillCandidate] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var grouped: [String: Set<UUID>] = [:]
        for token in tokens where token.amount > 0 && (token.role.isPositive || token.role.isBorrow) {
            let override = overrideMap[token.assetId]
            if override?.manualPriceUSD != nil, normalizedID(override?.coinGeckoIdOverride) == nil {
                continue
            }
            guard let coinGeckoId = normalizedID(override?.coinGeckoIdOverride) ?? normalizedID(token.coinGeckoId) else {
                continue
            }
            grouped[coinGeckoId, default: []].insert(token.assetId)
        }
        return grouped
            .map { coinGeckoId, ids in
                HistoricalBackfillCandidate(
                    coinGeckoId: coinGeckoId,
                    assetIds: ids.sorted { $0.uuidString < $1.uuidString })
            }
            .sorted { $0.coinGeckoId < $1.coinGeckoId }
    }

    private static func normalizedID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

enum HistoricalPriceCacheWriter {
    @MainActor
    static func upsert(
        _ dtos: [HistoricalPriceDTO],
        in context: ModelContext,
        fetchedAt: Date = .now) throws -> HistoricalBackfillWriteResult {
        let existing = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
        var existingByKey = Dictionary(
            existing.map { (HistoricalPriceCacheKey(coinGeckoId: $0.coinGeckoId, day: $0.day), $0) },
            uniquingKeysWith: { lhs, rhs in lhs.fetchedAt >= rhs.fetchedAt ? lhs : rhs })
        var inserted = 0
        var updated = 0

        for dto in dtos {
            let cacheKey = HistoricalPriceCacheKey(coinGeckoId: dto.coinGeckoId, day: dto.day)
            if let row = existingByKey[cacheKey] {
                row.usdPrice = dto.usdPrice
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
    }

    @MainActor
    static func clear(in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<HistoricalPricePoint>())
        for row in rows {
            context.delete(row)
        }
        try context.save()
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
