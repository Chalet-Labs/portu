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
    case zerion(OnchainTokenIdentity)
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
        /// CoinGecko/Zerion returned 429 and the runner exhausted its retry.
        case rateLimited
        /// Provider rejected our credentials (or none were configured).
        case unauthorized(provider: String)
        /// Backfill couldn't be started because nothing was fetchable — for example
        /// every candidate is onchain but no Zerion key is configured.
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

/// One run's valued tokens with the overrides they were valued with. The only way to build one is
/// to value inputs, so the resolvers can never read tokens and overrides that disagree.
struct HistoricalBackfillValuedTokens {
    let tokens: [ValuedToken]
    let overridesByAssetId: [UUID: TokenPricingOverrideSnapshot]

    init(
        _ inputs: [ValuationInput],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot]) {
        self.tokens = PortfolioValuation(inputs: inputs, market: MarketPrices(), overrides: overrides, mappings: mappings).tokens
        self.overridesByAssetId = TokenPricingOverrideFeature.overridesByAssetId(overrides)
    }
}

enum HistoricalBackfillCandidateResolver {
    /// One run's tokens, valued once over an empty market (S12): backfill has no live book or
    /// closes, so a token is worth its manual price × amount, else its sync value, as it always was.
    static func valuedTokens(
        _ inputs: [ValuationInput],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot] = []) -> HistoricalBackfillValuedTokens {
        HistoricalBackfillValuedTokens(inputs, overrides: overrides, mappings: mappings)
    }

    static func candidates(
        valued: HistoricalBackfillValuedTokens,
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        mappings: [TokenIdentityMappingSnapshot] = [],
        dashboardSettings: TokenDashboardSettings = .defaults,
        resolvedCoinGeckoIDs: [OnchainTokenIdentity: String] = [:]) -> [HistoricalBackfillCandidate] {
        let overrideMap = valued.overridesByAssetId
        let mappingMap = TokenIdentityMappingFeature.mappingsByIdentity(mappings)
        var grouped: [HistoricalBackfillCandidateKey: Set<UUID>] = [:]
        for valuedToken in valued.tokens where shouldIncludeToken(valuedToken, dashboardSettings: dashboardSettings) {
            let token = valuedToken.token
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
        valued: HistoricalBackfillValuedTokens,
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        dashboardSettings: TokenDashboardSettings = .defaults) -> Set<UUID> {
        let overrideMap = valued.overridesByAssetId
        let tokenIDs = valued.tokens.compactMap { token -> UUID? in
            shouldIncludeToken(token, dashboardSettings: dashboardSettings) ? token.token.assetId : nil
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
        valued: HistoricalBackfillValuedTokens,
        snapshots: [HistoricalBackfillSnapshotEntry] = [],
        mappings: [TokenIdentityMappingSnapshot] = [],
        dashboardSettings: TokenDashboardSettings = .defaults) -> [OnchainTokenIdentity] {
        let overrideMap = valued.overridesByAssetId
        let mappingMap = TokenIdentityMappingFeature.mappingsByIdentity(mappings)
        var identities = Set<OnchainTokenIdentity>()
        for valuedToken in valued.tokens where shouldIncludeToken(valuedToken, dashboardSettings: dashboardSettings) {
            let token = valuedToken.token
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
            if $0.chain.rawValue != $1.chain.rawValue {
                return $0.chain.rawValue < $1.chain.rawValue
            }
            return $0.contractAddress < $1.contractAddress
        }
    }

    /// Backfill's own per-token rule (S12) on the selection value: counted and not ignored,
    /// alwaysShow wins, then the unpriced and dust toggles against the USD threshold.
    private static func shouldIncludeToken(
        _ token: ValuedToken,
        dashboardSettings: TokenDashboardSettings) -> Bool {
        guard token.isCounted, let value = token.selectionValue else { return false }
        if token.alwaysShow {
            return true
        }
        if value == 0 {
            return !dashboardSettings.hideUnpriced
        }
        if value < dashboardSettings.dustThresholdUSD {
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
        if override?.alwaysShow == true {
            return true
        }

        let netValue = snapshotValue(snapshot, override: override)
        if netValue == 0 {
            return !dashboardSettings.hideUnpriced
        }
        if abs(netValue) < dashboardSettings.dustThresholdUSD {
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
        let overrideCoinGeckoID = TokenIdentityMappingFeature.normalizedProviderID(asset.override?.coinGeckoIdOverride)
        if asset.override?.manualPriceUSD != nil, overrideCoinGeckoID == nil {
            return
        }

        let explicitCoinGeckoID = overrideCoinGeckoID
            ?? TokenIdentityMappingFeature.normalizedProviderID(asset.coinGeckoId)
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
            ?? TokenIdentityMappingFeature.normalizedProviderID(resolvedCoinGeckoIDs[onchainIdentity])
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
                    source: .zerion(onchainIdentity)),
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

    private static func shouldResolveOnchain(
        coinGeckoId: String?,
        override: TokenPricingOverrideSnapshot?) -> Bool {
        let overrideCoinGeckoID = TokenIdentityMappingFeature.normalizedProviderID(override?.coinGeckoIdOverride)
        if override?.manualPriceUSD != nil, overrideCoinGeckoID == nil {
            return false
        }
        return overrideCoinGeckoID == nil && TokenIdentityMappingFeature.normalizedProviderID(coinGeckoId) == nil
    }
}

private struct HistoricalBackfillCandidateKey: Hashable {
    let historicalPriceID: String
    let source: HistoricalBackfillPriceSource

    init(historicalPriceID: String, source: HistoricalBackfillPriceSource) {
        self.historicalPriceID = OnchainTokenIdentity.normalizedHistoricalPriceID(historicalPriceID)
        self.source = source
    }
}

extension HistoricalBackfillPriceSource: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .coingecko(id):
            hasher.combine("coingecko")
            hasher.combine(TokenIdentityMappingFeature.normalizedProviderID(id))
        case let .zerion(identity):
            hasher.combine("zerion")
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
            HistoricalPriceCacheKey(coinGeckoId: $0.coinGeckoId, day: $0.day, currency: $0.currency)
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
            // for (coinGeckoId, day, currency) is enforced here by scoped upsert and dedupe.
            let groupedExisting = Dictionary(grouping: existing) {
                HistoricalPriceCacheKey(coinGeckoId: $0.coinGeckoId, day: $0.day, currency: $0.fiatCurrency)
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
                let cacheKey = HistoricalPriceCacheKey(coinGeckoId: dto.coinGeckoId, day: dto.day, currency: dto.currency)
                if let row = existingByKey[cacheKey] {
                    row.price = dto.price
                    row.source = dto.source
                    row.fetchedAt = fetchedAt
                    // Migrate legacy rows persisted before the currency column existed
                    // (currency == nil, treated as USD) to an explicit value.
                    row.currency = dto.currency
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
    let currency: FiatCurrency

    init(coinGeckoId: String, day: Date, currency: FiatCurrency) {
        self.coinGeckoId = OnchainTokenIdentity.normalizedHistoricalPriceID(coinGeckoId)
        self.day = HistoricalPriceCalendar.utcStartOfDay(for: day)
        self.currency = currency
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
