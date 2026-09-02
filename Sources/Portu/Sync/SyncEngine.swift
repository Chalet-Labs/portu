import Foundation
import os
import PortuCore
import PortuNetwork
import SwiftData

@MainActor
final class SyncEngine: @unchecked Sendable {
    private let modelContext: ModelContext
    private let providerFactory: ProviderFactory
    #if DEBUG
        var upsertAssetOverride: ((TokenDTO) throws -> Asset)?
    #endif

    init(modelContext: ModelContext, providerFactory: ProviderFactory) {
        self.modelContext = modelContext
        self.providerFactory = providerFactory
    }

    // MARK: - Public API

    func sync() async throws -> SyncResult {
        let activeSyncable = try fetchActiveSyncableAccounts()
        let activeManual = try fetchActiveManualAccounts()

        return try await sync(activeSyncable: activeSyncable, activeManual: activeManual)
    }

    func sync(scope: PortfolioSyncScope) async throws -> SyncResult {
        let activeSyncable = try fetchActiveSyncableAccounts(scope: scope)
        guard !activeSyncable.isEmpty else {
            return SyncResult(failedAccounts: [])
        }
        return try await sync(activeSyncable: activeSyncable, activeManual: [])
    }

    func sync(accountID: UUID) async throws -> SyncResult {
        let account = try fetchAccount(id: accountID)
        guard account.isActive else {
            throw SyncError.accountInactive
        }
        guard account.dataSource != .zapper else {
            throw SyncError.unsupportedLegacyAccount
        }
        guard account.isSyncable else {
            throw SyncError.accountNotSyncable
        }

        return try await sync(
            activeSyncable: [account],
            activeManual: [])
    }

    private func sync(
        activeSyncable: [Account],
        activeManual: [Account]) async throws -> SyncResult {
        guard !activeSyncable.isEmpty || !activeManual.isEmpty else {
            throw SyncError.noActiveAccounts
        }

        let attemptedSyncableAccountIDs = Set(activeSyncable.map(\.id))

        // ── Phase A: Per-account fetch + persist ──
        var failedAccounts: [String] = []
        var refreshedSyncableAccountIDs: Set<UUID> = []

        for account in activeSyncable {
            do {
                try await syncAccount(account)
                refreshedSyncableAccountIDs.insert(account.id)
            } catch {
                account.lastSyncError = error.localizedDescription
                failedAccounts.append(account.name)
            }
        }

        // ── Phase B: Snapshot all tiers ──
        let allSyncAttemptedFailed = failedAccounts.count == activeSyncable.count
        if allSyncAttemptedFailed, activeManual.isEmpty, !activeSyncable.isEmpty {
            try modelContext.save()
            throw SyncError.allAccountsFailed
        }

        let isPartialSnapshot = try hasActiveSyncableAccounts(outside: attemptedSyncableAccountIDs) || !failedAccounts.isEmpty
        try createSnapshots(
            isPartial: isPartialSnapshot,
            refreshedSyncableAccountIDs: refreshedSyncableAccountIDs)

        return SyncResult(failedAccounts: failedAccounts)
    }

    // MARK: - Phase A: Per-account sync

    private func syncAccount(_ account: Account) async throws {
        let context = SyncContext(
            accountId: account.id,
            kind: account.kind,
            addresses: account.addresses.map { ($0.address, $0.chain) },
            exchangeType: account.exchangeType)

        let provider = try resolveProvider(for: account, context: context)

        let allDTOs = try await provider.fetchPositions(context: context)

        // ── Build phase: stage rebuild data as value types ──
        // No @Model objects are constructed here — `Position` and `PositionToken`
        // would auto-register with the ModelContext as soon as a relationship to
        // an already-managed object (e.g. the resolved Asset) is set during init.
        // Staging with plain structs keeps the build phase truly side-effect-free
        // for Position/PositionToken rows (#31). Asset side effects are bounded:
        // upsertAsset may insert a new Asset row or run updateAssetMetadata on an
        // existing one, and the subsequent save() of `lastSyncError` flushes
        // those mutations. They are self-healing — the 3-tier dedup hierarchy in
        // upsertAsset prevents duplicate Asset accumulation across repeated
        // partial failures, and the append-only key backfill never overwrites
        // existing identity keys.
        var staged: [StagedPosition] = []
        var assetLookup = try makeAssetLookup()

        for dto in allDTOs {
            var net: Decimal = 0
            var tokens: [StagedToken] = []
            for tokenDTO in dto.tokens {
                let asset = try upsertAsset(from: tokenDTO, lookup: &assetLookup)
                tokens.append(StagedToken(
                    role: tokenDTO.role,
                    amount: tokenDTO.amount,
                    usdValue: tokenDTO.usdValue,
                    asset: asset))

                if tokenDTO.role.isPositive {
                    net += tokenDTO.usdValue
                } else if tokenDTO.role.isBorrow {
                    net -= tokenDTO.usdValue
                }
                // reward: excluded from net
            }

            staged.append(StagedPosition(
                positionType: dto.positionType,
                chain: dto.chain,
                protocolId: dto.protocolId,
                protocolName: dto.protocolName,
                protocolLogoURL: dto.protocolLogoURL,
                healthFactor: dto.healthFactor,
                netUSDValue: net,
                tokens: tokens))
        }

        // ── Commit phase: all DTOs succeeded — replace positions ──
        // Note: this still uses the main ModelContext, not a scratch context, so
        // a throw from save() after the delete loop would leave the account
        // without positions until the next successful sync. The build-phase
        // isolation in #31 covers the upsertAsset-throws path; commit-phase
        // resilience would require a child ModelContext (tracked separately).
        // Snapshot account.positions before deletion — it's a live SwiftData
        // relationship array that mutates during cascade deletes.
        for position in Array(account.positions) {
            modelContext.delete(position)
        }

        for entry in staged {
            let position = Position(
                positionType: entry.positionType,
                chain: entry.chain,
                protocolId: entry.protocolId,
                protocolName: entry.protocolName,
                protocolLogoURL: entry.protocolLogoURL,
                healthFactor: entry.healthFactor,
                netUSDValue: entry.netUSDValue,
                syncedAt: .now)
            // Insert before assigning the inverse relationship so SwiftData has
            // a managed object on both sides when the inverse hook fires.
            modelContext.insert(position)
            position.account = account
            for stagedToken in entry.tokens {
                let token = PositionToken(
                    role: stagedToken.role,
                    amount: stagedToken.amount,
                    usdValue: stagedToken.usdValue,
                    asset: stagedToken.asset)
                modelContext.insert(token)
                token.position = position
            }
        }

        account.lastSyncedAt = .now
        account.lastSyncError = nil
        try modelContext.save()
    }

    // MARK: - Asset Upsert (3-tier hierarchy)

    /// Internal (not private) — called directly by upsert/dedup tests.
    func upsertAsset(from dto: TokenDTO) throws -> Asset {
        var lookup = try makeAssetLookup()
        return try upsertAsset(from: dto, lookup: &lookup)
    }

    private func upsertAsset(from dto: TokenDTO, lookup: inout AssetLookupCache) throws -> Asset {
        #if DEBUG
            if let override = upsertAssetOverride {
                let asset = try override(dto)
                lookup.record(asset)
                return asset
            }
        #endif
        // Tier 1: coinGeckoId
        if let cgId = normalizedUpsertKey(dto.coinGeckoId) {
            if let existing = lookup.asset(coinGeckoId: cgId) {
                updateAssetMetadata(existing, from: dto)
                lookup.record(existing)
                return existing
            }
        }

        // Tier 2: upsertChain + upsertContract
        if let chain = dto.chain, let contract = normalizedUpsertKey(dto.contractAddress) {
            if let existing = lookup.asset(chain: chain, contract: contract) {
                updateAssetMetadata(existing, from: dto)
                lookup.record(existing)
                return existing
            }
        }

        // Tier 3: sourceKey
        if let key = normalizedUpsertKey(dto.sourceKey) {
            if let existing = lookup.asset(sourceKey: key) {
                updateAssetMetadata(existing, from: dto)
                lookup.record(existing)
                return existing
            }
        }

        // No match → create new Asset
        let asset = Asset(
            symbol: dto.symbol,
            name: dto.name,
            coinGeckoId: normalizedUpsertKey(dto.coinGeckoId),
            upsertChain: dto.chain,
            upsertContract: normalizedUpsertKey(dto.contractAddress),
            sourceKey: normalizedUpsertKey(dto.sourceKey),
            debankId: normalizedUpsertKey(dto.debankId),
            logoURL: dto.logoURL,
            category: dto.category,
            isVerified: dto.isVerified)
        modelContext.insert(asset)
        lookup.record(asset)
        return asset
    }

    /// Metadata update: last-synced-wins for name, category, logoURL, isVerified.
    /// Upsert keys (coinGeckoId, upsertChain, upsertContract, sourceKey) are append-only.
    private func updateAssetMetadata(_ asset: Asset, from dto: TokenDTO) {
        asset.symbol = dto.symbol
        asset.name = dto.name
        asset.category = dto.category
        asset.logoURL = dto.logoURL ?? asset.logoURL

        if dto.isVerified {
            asset.isVerified = true
        }

        // Append-only: fill in missing keys, never overwrite
        if asset.coinGeckoId == nil, let cgId = normalizedUpsertKey(dto.coinGeckoId) {
            asset.coinGeckoId = cgId
        }
        if asset.sourceKey == nil, let key = normalizedUpsertKey(dto.sourceKey) {
            asset.sourceKey = key
        }
        if asset.upsertChain == nil, let chain = dto.chain {
            asset.upsertChain = chain
        }
        if
            asset.upsertContract == nil,
            let contract = normalizedUpsertKey(dto.contractAddress),
            let dtoChain = dto.chain,
            asset.upsertChain == dtoChain {
            asset.upsertContract = contract
        }
        if asset.debankId == nil, let dbId = normalizedUpsertKey(dto.debankId) {
            asset.debankId = dbId
        }
    }

    // MARK: - Phase B: Snapshots

    private func createSnapshots(
        isPartial: Bool,
        refreshedSyncableAccountIDs: Set<UUID>) throws {
        let batchId = UUID()
        let batchTimestamp = Date.now

        // Prefetch all throwing queries before any inserts to avoid staged
        // orphan snapshots if a fetch fails mid-way.
        let allPositionsDescriptor = FetchDescriptor<Position>()
        let allPositions = try modelContext.fetch(allPositionsDescriptor)
            .filter { $0.account?.isActive == true }
        let activeAccounts = try fetchAllActiveAccounts()

        createPortfolioSnapshot(batchId: batchId, timestamp: batchTimestamp, positions: allPositions, isPartial: isPartial)
        createAccountSnapshots(
            batchId: batchId,
            timestamp: batchTimestamp,
            accounts: activeAccounts,
            refreshedSyncableAccountIDs: refreshedSyncableAccountIDs)
        createAssetSnapshots(
            batchId: batchId,
            timestamp: batchTimestamp,
            positions: allPositions,
            refreshedSyncableAccountIDs: refreshedSyncableAccountIDs)

        pruneSnapshots()
        try modelContext.save()
    }

    private func createPortfolioSnapshot(batchId: UUID, timestamp: Date, positions: [Position], isPartial: Bool) {
        var totalValue: Decimal = 0
        var idleValue: Decimal = 0
        var deployedValue: Decimal = 0
        var debtValue: Decimal = 0

        for pos in positions {
            totalValue += pos.netUSDValue

            switch pos.positionType {
            case .idle:
                let posIdle = pos.tokens
                    .filter(\.role.isPositive)
                    .reduce(Decimal.zero) { $0 + $1.usdValue }
                idleValue += posIdle
            case .lending, .staking, .farming, .liquidityPool:
                let posDep = pos.tokens
                    .filter(\.role.isPositive)
                    .reduce(Decimal.zero) { $0 + $1.usdValue }
                deployedValue += posDep
            default:
                break
            }

            let posBorrow = pos.tokens
                .filter(\.role.isBorrow)
                .reduce(Decimal.zero) { $0 + $1.usdValue }
            debtValue += posBorrow
        }

        let snap = PortfolioSnapshot(
            syncBatchId: batchId, timestamp: timestamp,
            totalValue: totalValue, idleValue: idleValue,
            deployedValue: deployedValue, debtValue: debtValue,
            isPartial: isPartial)
        modelContext.insert(snap)
    }

    private func createAccountSnapshots(
        batchId: UUID,
        timestamp: Date,
        accounts: [Account],
        refreshedSyncableAccountIDs: Set<UUID>) {
        for account in accounts {
            let accountTotal = account.positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
            let isFresh = account.dataSource == .manual ||
                (refreshedSyncableAccountIDs.contains(account.id) && account.lastSyncError == nil)

            let snap = AccountSnapshot(
                syncBatchId: batchId, timestamp: timestamp,
                accountId: account.id, totalValue: accountTotal, isFresh: isFresh)
            modelContext.insert(snap)
        }
    }

    private func createAssetSnapshots(
        batchId: UUID,
        timestamp: Date,
        positions: [Position],
        refreshedSyncableAccountIDs: Set<UUID>) {
        for snap in Self.accumulatedAssetSnapshots(
            batchId: batchId,
            timestamp: timestamp,
            positions: positions,
            refreshedSyncableAccountIDs: refreshedSyncableAccountIDs) {
            modelContext.insert(snap)
        }
    }

    // MARK: - Snapshot Pruning

    private let snapshotStore = SnapshotStore()

    private static let logger = Logger(subsystem: "com.portu.app", category: "SyncEngine")

    /// Best-effort pruning — errors are logged but don't fail the sync.
    private func pruneSnapshots() {
        let now = Date.now
        pruneSnapshotType(PortfolioSnapshot.self, now: now)
        pruneSnapshotType(AccountSnapshot.self, now: now)
        pruneSnapshotType(AssetSnapshot.self, now: now)
    }

    private func pruneSnapshotType<T: PersistentModel & Timestamped>(_: T.Type, now: Date) {
        do {
            let all = try modelContext.fetch(FetchDescriptor<T>())
            let allDates = all.map(\.timestamp)
            let retainedDates = Set(snapshotStore.prune(snapshotDates: allDates, now: now))
            for snapshot in all where !retainedDates.contains(snapshot.timestamp) {
                modelContext.delete(snapshot)
            }
        } catch {
            Self.logger.error("Snapshot pruning failed for \(String(describing: T.self)): \(error)")
        }
    }

    // MARK: - Helpers

    private func resolveProvider(for account: Account, context: SyncContext) throws -> any PortfolioDataProvider {
        try providerFactory.makeProvider(for: account.dataSource, context: context)
    }

    // SwiftData predicates have limitations with enum comparisons and optional
    // properties. Plain Bool predicates (isActive) are safe; enum and Optional<String>
    // filters use in-memory filtering to avoid runtime crashes.

    private func fetchActiveSyncableAccounts() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>()
        return try modelContext.fetch(descriptor).filter(\.isSyncable)
    }

    private func hasActiveSyncableAccounts(outside accountIDs: Set<UUID>) throws -> Bool {
        try fetchActiveSyncableAccounts().contains { accountIDs.contains($0.id) == false }
    }

    private func fetchActiveSyncableAccounts(scope: PortfolioSyncScope) throws -> [Account] {
        try fetchActiveSyncableAccounts().filter { account in
            switch scope {
            case .onchain:
                account.dataSource == .zerion
            case .exchange:
                account.dataSource == .exchange
            }
        }
    }

    private func fetchActiveManualAccounts() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>()
        return try modelContext.fetch(descriptor).filter { $0.isActive && $0.dataSource == .manual }
    }

    private func fetchAllActiveAccounts() throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.isActive })
        return try modelContext.fetch(descriptor)
    }

    private func fetchAccount(id: UUID) throws -> Account {
        var descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let account = try modelContext.fetch(descriptor).first else {
            throw SyncError.accountNotFound
        }
        return account
    }

    private func makeAssetLookup() throws -> AssetLookupCache {
        try AssetLookupCache(assets: modelContext.fetch(FetchDescriptor<Asset>()))
    }

    private func normalizedUpsertKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
