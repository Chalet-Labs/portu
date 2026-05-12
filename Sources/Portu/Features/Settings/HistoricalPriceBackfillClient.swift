import ComposableArchitecture
import Foundation
import PortuCore
import SwiftData

struct HistoricalPriceBackfillClient {
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
        now: @escaping @Sendable () -> Date = { .now }) -> Self {
        Self(
            run: {
                try await BackfillRunner(
                    modelContext: modelContext,
                    priceService: priceService,
                    now: now).run()
            },
            clearCache: {
                try HistoricalPriceCacheWriter.clear(in: modelContext)
            })
    }
}

@MainActor
private struct BackfillRunner {
    let modelContext: ModelContext
    let priceService: PriceServiceClient
    let now: @Sendable () -> Date

    func run() async throws -> HistoricalBackfillResult {
        let tokens = try modelContext.fetch(FetchDescriptor<PositionToken>())
        let overrides = try modelContext.fetch(FetchDescriptor<TokenPricingOverride>())
        let entries = TokenEntry.fromActiveTokens(tokens)
        let overrideSnapshots = overrides.map(TokenPricingOverrideSnapshot.init)
        let candidates = HistoricalBackfillCandidateResolver.candidates(
            tokens: entries,
            overrides: overrideSnapshots)

        var inserted = 0
        var updated = 0
        var fetched = 0
        var failures: [String] = []
        let skipped = max(0, Set(entries.map(\.assetId)).count - candidates.flatMap(\.assetIds).count)
        let requested = candidates.reduce(0) { total, candidate in
            total + candidate.assetIds.count
        }

        for candidate in candidates {
            let prices: [HistoricalPriceDTO]
            do {
                prices = try await priceService.fetchHistoricalPrices(
                    candidate.coinGeckoId,
                    HistoricalPriceBackfillSettings.chartHorizonDays)
            } catch {
                failures.append(candidate.coinGeckoId)
                if failures.count == candidates.count {
                    throw error
                }
                continue
            }

            let write = try HistoricalPriceCacheWriter.upsert(prices, in: modelContext, fetchedAt: now())
            inserted += write.inserted
            updated += write.updated
            fetched += candidate.assetIds.count
        }

        return HistoricalBackfillResult(
            requestedAssets: requested,
            fetchedAssets: fetched,
            skippedAssets: skipped,
            insertedPoints: inserted,
            updatedPoints: updated,
            failedCoinGeckoIDs: failures)
    }
}
