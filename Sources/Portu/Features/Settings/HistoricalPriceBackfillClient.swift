import ComposableArchitecture
import Foundation
import PortuCore
import PortuNetwork
import SwiftData

struct HistoricalPriceBackfillClient {
    typealias Sleep = @MainActor @Sendable (Duration) async throws -> Void

    var run: @MainActor @Sendable () async throws -> HistoricalBackfillResult
    var clearCache: @MainActor @Sendable () async throws -> Void
}

extension HistoricalPriceBackfillClient: DependencyKey {
    static let liveValue = Self(
        run: { fatalError("HistoricalPriceBackfillClient.liveValue must be overridden at Store creation") },
        clearCache: { fatalError("HistoricalPriceBackfillClient.liveValue must be overridden at Store creation") })

    static let testValue = Self(
        run: { HistoricalBackfillResult(
            requestedAssets: 0,
            fetchedAssets: 0,
            skippedAssets: 0,
            insertedPoints: 0,
            updatedPoints: 0,
            failedCoinGeckoIDs: []) },
        clearCache: {})
}

extension DependencyValues {
    var historicalPriceBackfill: HistoricalPriceBackfillClient {
        get { self[HistoricalPriceBackfillClient.self] }
        set { self[HistoricalPriceBackfillClient.self] = newValue }
    }
}

extension HistoricalPriceBackfillClient {
    @MainActor
    static func live(
        modelContext: ModelContext,
        priceService: PriceServiceClient,
        now: @escaping @Sendable () -> Date = { .now },
        dashboardSettings: @escaping @MainActor @Sendable () -> TokenDashboardSettings = { .defaults },
        requestSpacing: Duration = .seconds(8),
        rateLimitRetryDelay: Duration = .seconds(60),
        sleep: @escaping Sleep = { duration in try await Task.sleep(for: duration) }) -> Self {
        Self(
            run: {
                try await BackfillRunner(
                    modelContext: modelContext,
                    priceService: priceService,
                    now: now,
                    dashboardSettings: dashboardSettings,
                    requestSpacing: requestSpacing,
                    rateLimitRetryDelay: rateLimitRetryDelay,
                    sleep: sleep).run()
            },
            clearCache: {
                try HistoricalPriceCacheWriter.clear(in: modelContext)
            })
    }
}

@MainActor
private struct HistoricalBackfillSourceData {
    let tokens: [TokenEntry]
    let snapshots: [HistoricalBackfillSnapshotEntry]
    let overrides: [TokenPricingOverrideSnapshot]
    let mappings: [TokenIdentityMappingSnapshot]
    let liveMappings: [TokenIdentityMapping]
}

private struct HistoricalBackfillFetchResult {
    var inserted = 0
    var updated = 0
    var fetched = 0
    var failures: [String] = []
}

@MainActor
private struct BackfillRunner {
    let modelContext: ModelContext
    let priceService: PriceServiceClient
    let now: @Sendable () -> Date
    let dashboardSettings: @MainActor @Sendable () -> TokenDashboardSettings
    let requestSpacing: Duration
    let rateLimitRetryDelay: Duration
    let sleep: HistoricalPriceBackfillClient.Sleep

    func run() async throws -> HistoricalBackfillResult {
        let settings = dashboardSettings()
        let sourceData = try loadSourceData()
        let identitiesNeedingResolution = HistoricalBackfillCandidateResolver.onchainIdentitiesNeedingResolution(
            tokens: sourceData.tokens,
            snapshots: sourceData.snapshots,
            overrides: sourceData.overrides,
            mappings: sourceData.mappings,
            dashboardSettings: settings)
        let resolvedCoinGeckoIDs = try await resolveCoinGeckoIDs(for: identitiesNeedingResolution)
        try persistResolvedCoinGeckoIDs(
            resolvedCoinGeckoIDs,
            existingMappings: sourceData.liveMappings)
        let candidates = HistoricalBackfillCandidateResolver.candidates(
            tokens: sourceData.tokens,
            snapshots: sourceData.snapshots,
            overrides: sourceData.overrides,
            mappings: sourceData.mappings,
            dashboardSettings: settings,
            resolvedCoinGeckoIDs: resolvedCoinGeckoIDs)
        let sourceAssetCount = HistoricalBackfillCandidateResolver.sourceAssetIDs(
            tokens: sourceData.tokens,
            snapshots: sourceData.snapshots,
            overrides: sourceData.overrides,
            dashboardSettings: settings).count
        let requested = candidates.reduce(0) { total, candidate in
            total + candidate.assetIds.count
        }
        let fetchResult = try await fetchCandidates(candidates)

        return HistoricalBackfillResult(
            requestedAssets: requested,
            fetchedAssets: fetchResult.fetched,
            skippedAssets: max(0, sourceAssetCount - candidates.flatMap(\.assetIds).count),
            insertedPoints: fetchResult.inserted,
            updatedPoints: fetchResult.updated,
            failedCoinGeckoIDs: fetchResult.failures)
    }

    private func loadSourceData() throws -> HistoricalBackfillSourceData {
        let tokens = try modelContext.fetch(FetchDescriptor<PositionToken>())
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let assetSnapshots = try modelContext.fetch(FetchDescriptor<AssetSnapshot>())
        let overrides = try modelContext.fetch(FetchDescriptor<TokenPricingOverride>())
        let mappings = try modelContext.fetch(FetchDescriptor<TokenIdentityMapping>())
        let entries = TokenEntry.fromActiveTokens(tokens)
        let assetsById = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let snapshotEntries = assetSnapshots.map { snapshot in
            let asset = assetsById[snapshot.assetId]
            return HistoricalBackfillSnapshotEntry(
                assetId: snapshot.assetId,
                coinGeckoId: asset?.coinGeckoId,
                onchainIdentity: OnchainTokenIdentity(chain: asset?.upsertChain, contractAddress: asset?.upsertContract),
                amount: snapshot.amount,
                borrowAmount: snapshot.borrowAmount,
                usdValue: snapshot.usdValue,
                borrowUsdValue: snapshot.borrowUsdValue)
        }
        let overrideSnapshots = overrides.map(TokenPricingOverrideSnapshot.init)
        let mappingSnapshots = mappings.map(TokenIdentityMappingSnapshot.init)

        return HistoricalBackfillSourceData(
            tokens: entries,
            snapshots: snapshotEntries,
            overrides: overrideSnapshots,
            mappings: mappingSnapshots,
            liveMappings: mappings)
    }

    private func resolveCoinGeckoIDs(
        for identities: [OnchainTokenIdentity]) async throws -> [OnchainTokenIdentity: String] {
        do {
            return try await priceService.resolveCoinGeckoIDs(identities)
        } catch {
            return [:]
        }
    }

    private func fetchCandidates(_ candidates: [HistoricalBackfillCandidate]) async throws -> HistoricalBackfillFetchResult {
        var result = HistoricalBackfillFetchResult()
        let canFetchZapperHistoricalPrices = priceService.canFetchZapperHistoricalPrices()
        let unavailableZapperCandidates = canFetchZapperHistoricalPrices
            ? []
            : candidates.filter { candidate in
                if case .zapper = candidate.source { return true }
                return false
            }
        let runnableCandidates = canFetchZapperHistoricalPrices
            ? candidates
            : candidates.filter { candidate in
                if case .zapper = candidate.source { return false }
                return true
            }

        var hasRequestedCandidate = false
        result.failures.append(contentsOf: unavailableZapperCandidates.map(\.historicalPriceID))
        for candidate in runnableCandidates {
            let prices: [HistoricalPriceDTO]
            do {
                if hasRequestedCandidate {
                    try await sleep(requestSpacing)
                }
                hasRequestedCandidate = true
                prices = try await fetchHistoricalPrices(for: candidate)
            } catch {
                if error is CancellationError {
                    throw error
                }
                result.failures.append(candidate.historicalPriceID)
                if result.failures.count == candidates.count {
                    throw error
                }
                continue
            }

            let write = try HistoricalPriceCacheWriter.upsert(
                prices.rekeyed(to: candidate.historicalPriceID),
                in: modelContext,
                fetchedAt: now())
            result.inserted += write.inserted
            result.updated += write.updated
            result.fetched += candidate.assetIds.count
        }
        return result
    }

    private func fetchHistoricalPrices(for candidate: HistoricalBackfillCandidate) async throws -> [HistoricalPriceDTO] {
        switch candidate.source {
        case let .coingecko(coinGeckoID):
            do {
                return try await priceService.fetchHistoricalPrices(
                    coinGeckoID,
                    HistoricalPriceBackfillSettings.chartHorizonDays)
            } catch PriceServiceError.rateLimited {
                try await sleep(rateLimitRetryDelay)
                return try await priceService.fetchHistoricalPrices(
                    coinGeckoID,
                    HistoricalPriceBackfillSettings.chartHorizonDays)
            }
        case let .zapper(identity):
            do {
                return try await priceService.fetchZapperHistoricalPrices(
                    identity,
                    HistoricalPriceBackfillSettings.chartHorizonDays)
            } catch ZapperError.rateLimited {
                try await sleep(rateLimitRetryDelay)
                return try await priceService.fetchZapperHistoricalPrices(
                    identity,
                    HistoricalPriceBackfillSettings.chartHorizonDays)
            }
        }
    }

    private func persistResolvedCoinGeckoIDs(
        _ resolvedCoinGeckoIDs: [OnchainTokenIdentity: String],
        existingMappings: [TokenIdentityMapping]) throws {
        guard !resolvedCoinGeckoIDs.isEmpty else { return }
        for (identity, coinGeckoID) in resolvedCoinGeckoIDs {
            try TokenIdentityMappingWriter.upsert(
                identity: identity,
                coinGeckoId: coinGeckoID,
                mappings: existingMappings,
                in: modelContext,
                now: now())
        }
    }
}

enum TokenIdentityMappingWriter {
    @MainActor
    static func upsert(
        identity: OnchainTokenIdentity,
        coinGeckoId: String,
        mappings: [TokenIdentityMapping],
        in context: ModelContext,
        now: Date = .now) throws {
        guard let normalizedID = TokenIdentityMapping.normalizedProviderID(coinGeckoId) else {
            return
        }

        let canonicalKey = TokenIdentityMapping.canonicalKey(for: identity)
        let matches = mappings
            .filter { $0.canonicalKey == canonicalKey }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.updatedAt > rhs.updatedAt
            }

        if let mapping = matches.first {
            mapping.chain = identity.chain
            mapping.contractAddress = identity.contractAddress
            mapping.canonicalKey = canonicalKey
            mapping.updateCoinGeckoId(normalizedID, resolvedAt: now)
            for duplicate in matches.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            context.insert(TokenIdentityMapping(
                identity: identity,
                coinGeckoId: normalizedID,
                coinGeckoResolvedAt: now,
                createdAt: now,
                updatedAt: now))
        }

        try context.save()
    }
}

private extension [HistoricalPriceDTO] {
    func rekeyed(to priceID: String) -> [HistoricalPriceDTO] {
        map {
            HistoricalPriceDTO(
                coinGeckoId: priceID,
                timestamp: $0.timestamp,
                usdPrice: $0.usdPrice,
                source: $0.source)
        }
    }
}
