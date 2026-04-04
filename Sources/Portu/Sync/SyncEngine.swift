import Foundation
import PortuCore
import PortuNetwork
import SwiftData

@MainActor
final class SyncEngine: @unchecked Sendable {
    private let modelContext: ModelContext
    private let secretStore: any SecretStore

    init(modelContext: ModelContext, secretStore: any SecretStore) {
        self.modelContext = modelContext
        self.secretStore = secretStore
    }

    // MARK: - Public API

    func sync() async throws -> SyncResult {
        let activeSyncable = fetchActiveSyncableAccounts()
        let activeManual = fetchActiveManualAccounts()

        guard !activeSyncable.isEmpty || !activeManual.isEmpty else {
            throw SyncError.noActiveAccounts
        }

        // ── Phase A: Per-account fetch + persist ──
        var failedAccounts: [String] = []

        for account in activeSyncable {
            do {
                try await syncAccount(account)
            } catch {
                account.lastSyncError = error.localizedDescription
                failedAccounts.append(account.name)
            }
        }

        // ── Phase B: Snapshot all tiers ──
        let allSyncAttemptedFailed = failedAccounts.count == activeSyncable.count
        if allSyncAttemptedFailed, activeManual.isEmpty, !activeSyncable.isEmpty {
            throw SyncError.allAccountsFailed
        }

        try createSnapshots(isPartial: !failedAccounts.isEmpty)

        return SyncResult(failedAccounts: failedAccounts)
    }

    // MARK: - Phase A: Per-account sync

    private func syncAccount(_ account: Account) async throws {
        let context = SyncContext(
            accountId: account.id,
            kind: account.kind,
            addresses: account.addresses.map { ($0.address, $0.chain) },
            exchangeType: account.exchangeType)

        let provider = try resolveProvider(for: account)

        let balances = try await provider.fetchBalances(context: context)
        let defi = try await provider.fetchDeFiPositions(context: context)
        let allDTOs = balances + defi

        // Delete stale positions from previous sync
        for position in account.positions {
            modelContext.delete(position)
        }

        // Map DTOs → SwiftData
        for dto in allDTOs {
            let position = Position(
                positionType: dto.positionType,
                chain: dto.chain,
                protocolId: dto.protocolId,
                protocolName: dto.protocolName,
                protocolLogoURL: dto.protocolLogoURL,
                healthFactor: dto.healthFactor,
                account: account,
                syncedAt: .now)

            var net: Decimal = 0
            for tokenDTO in dto.tokens {
                let asset = upsertAsset(from: tokenDTO)
                let token = PositionToken(
                    role: tokenDTO.role,
                    amount: tokenDTO.amount,
                    usdValue: tokenDTO.usdValue,
                    asset: asset,
                    position: position)
                modelContext.insert(token)

                if tokenDTO.role.isPositive {
                    net += tokenDTO.usdValue
                } else if tokenDTO.role.isBorrow {
                    net -= tokenDTO.usdValue
                }
                // reward: excluded from net
            }

            position.netUSDValue = net
            modelContext.insert(position)
        }

        account.lastSyncedAt = .now
        account.lastSyncError = nil
        try modelContext.save()
    }

    // MARK: - Asset Upsert (3-tier hierarchy)

    func upsertAsset(from dto: TokenDTO) -> Asset {
        // Tier 1: coinGeckoId
        if let cgId = dto.coinGeckoId, !cgId.isEmpty {
            if let existing = fetchAsset(coinGeckoId: cgId) {
                updateAssetMetadata(existing, from: dto)
                return existing
            }
        }

        // Tier 2: upsertChain + upsertContract
        if let chain = dto.chain, let contract = dto.contractAddress, !contract.isEmpty {
            if let existing = fetchAsset(chain: chain, contract: contract) {
                updateAssetMetadata(existing, from: dto)
                return existing
            }
        }

        // Tier 3: sourceKey
        if let key = dto.sourceKey, !key.isEmpty {
            if let existing = fetchAsset(sourceKey: key) {
                updateAssetMetadata(existing, from: dto)
                return existing
            }
        }

        // No match → create new Asset
        let asset = Asset(
            symbol: dto.symbol,
            name: dto.name,
            coinGeckoId: dto.coinGeckoId.flatMap { $0.isEmpty ? nil : $0 },
            upsertChain: dto.chain,
            upsertContract: dto.contractAddress.flatMap { $0.isEmpty ? nil : $0 },
            sourceKey: dto.sourceKey.flatMap { $0.isEmpty ? nil : $0 },
            debankId: dto.debankId.flatMap { $0.isEmpty ? nil : $0 },
            logoURL: dto.logoURL,
            category: dto.category,
            isVerified: dto.isVerified)
        modelContext.insert(asset)
        return asset
    }

    /// Metadata update: last-synced-wins for name, category, logoURL, isVerified.
    /// Upsert keys (coinGeckoId, upsertChain, upsertContract, sourceKey) are append-only.
    private func updateAssetMetadata(_ asset: Asset, from dto: TokenDTO) {
        asset.symbol = dto.symbol
        asset.name = dto.name
        asset.category = dto.category
        asset.logoURL = dto.logoURL ?? asset.logoURL

        if dto.isVerified { asset.isVerified = true }

        // Append-only: fill in missing keys, never overwrite
        if asset.coinGeckoId == nil, let cgId = dto.coinGeckoId, !cgId.isEmpty { asset.coinGeckoId = cgId }
        if asset.sourceKey == nil, let key = dto.sourceKey, !key.isEmpty { asset.sourceKey = key }
        if asset.upsertChain == nil, let chain = dto.chain { asset.upsertChain = chain }
        if
            asset.upsertContract == nil,
            let contract = dto.contractAddress, !contract.isEmpty,
            let dtoChain = dto.chain,
            asset.upsertChain == dtoChain {
            asset.upsertContract = contract
        }
        if asset.debankId == nil, let dbId = dto.debankId, !dbId.isEmpty { asset.debankId = dbId }
    }

    // MARK: - Phase B: Snapshots

    private func createSnapshots(isPartial: Bool) throws {
        let batchId = UUID()
        let batchTimestamp = Date.now

        // Query all positions from active accounts — filter in memory to avoid
        // SwiftData predicate issues with optional chaining
        let allPositionsDescriptor = FetchDescriptor<Position>()
        let allPositions = try modelContext.fetch(allPositionsDescriptor)
            .filter { $0.account?.isActive == true }

        createPortfolioSnapshot(batchId: batchId, timestamp: batchTimestamp, positions: allPositions, isPartial: isPartial)
        createAccountSnapshots(batchId: batchId, timestamp: batchTimestamp)
        createAssetSnapshots(batchId: batchId, timestamp: batchTimestamp, positions: allPositions)

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

    private func createAccountSnapshots(batchId: UUID, timestamp: Date) {
        for account in fetchAllActiveAccounts() {
            let accountTotal = account.positions.reduce(Decimal.zero) { $0 + $1.netUSDValue }
            let isFresh = account.dataSource == .manual || account.lastSyncError == nil

            let snap = AccountSnapshot(
                syncBatchId: batchId, timestamp: timestamp,
                accountId: account.id, totalValue: accountTotal, isFresh: isFresh)
            modelContext.insert(snap)
        }
    }

    private func createAssetSnapshots(batchId: UUID, timestamp: Date, positions: [Position]) {
        var accumulators: [String: AssetSnapshotAccumulator] = [:]

        for pos in positions {
            guard let accountId = pos.account?.id else { continue }

            for token in pos.tokens {
                guard let asset = token.asset else { continue }
                if token.role.isReward { continue }

                let key = "\(accountId):\(asset.id)"

                if accumulators[key] == nil {
                    accumulators[key] = AssetSnapshotAccumulator(
                        accountId: accountId,
                        assetId: asset.id,
                        symbol: asset.symbol,
                        category: asset.category)
                }

                if token.role.isBorrow {
                    accumulators[key]!.borrowAmount += token.amount
                    accumulators[key]!.borrowUsdValue += token.usdValue
                } else {
                    accumulators[key]!.grossAmount += token.amount
                    accumulators[key]!.grossUsdValue += token.usdValue
                }
            }
        }

        for acc in accumulators.values {
            let snap = AssetSnapshot(
                syncBatchId: batchId, timestamp: timestamp,
                accountId: acc.accountId, assetId: acc.assetId,
                symbol: acc.symbol, category: acc.category,
                amount: acc.grossAmount, usdValue: acc.grossUsdValue,
                borrowAmount: acc.borrowAmount, borrowUsdValue: acc.borrowUsdValue)
            modelContext.insert(snap)
        }
    }

    // MARK: - Snapshot Pruning

    /// - Snapshots older than 7 days: keep one per day (last of each day)
    /// - Snapshots older than 90 days: keep one per week (last of each week)
    private func pruneSnapshots() {
        let now = Date.now
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now)!

        pruneSnapshotType(PortfolioSnapshot.self, olderThan: sevenDaysAgo, keepPer: .day)
        pruneSnapshotType(PortfolioSnapshot.self, olderThan: ninetyDaysAgo, keepPer: .weekOfYear)
        pruneSnapshotType(AccountSnapshot.self, olderThan: sevenDaysAgo, keepPer: .day)
        pruneSnapshotType(AccountSnapshot.self, olderThan: ninetyDaysAgo, keepPer: .weekOfYear)
        pruneSnapshotType(AssetSnapshot.self, olderThan: sevenDaysAgo, keepPer: .day)
        pruneSnapshotType(AssetSnapshot.self, olderThan: ninetyDaysAgo, keepPer: .weekOfYear)
    }

    private func pruneSnapshotType(_: (some PersistentModel).Type, olderThan _: Date, keepPer _: Calendar.Component) {
        // Implementation: fetch snapshots older than cutoff, group by calendar component,
        // keep only the last snapshot per group, delete the rest.
        // This is a best-effort operation — errors are logged but don't fail the sync.
        // TODO: Implement when snapshot volume warrants it
    }

    // MARK: - Helpers

    private func resolveProvider(for account: Account) throws -> any PortfolioDataProvider {
        switch account.dataSource {
        case .zapper:
            let apiKey: String
            do {
                guard let key = try secretStore.get(key: "portu.provider.zapper.apiKey") else {
                    throw SyncError.missingAPIKey("Zapper API key not configured")
                }
                apiKey = key
            } catch is KeychainError {
                throw SyncError.missingAPIKey("Failed to read Zapper API key from Keychain")
            }
            return ZapperProvider(apiKey: apiKey)
        case .exchange:
            return ExchangeProvider(secretStore: secretStore)
        case .manual:
            fatalError("Manual accounts should not reach provider resolution")
        }
    }

    // SwiftData predicates have limitations with enum comparisons.
    // Use FetchDescriptor without predicate and filter in memory for safety.

    private func fetchActiveSyncableAccounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.isActive && $0.dataSource != .manual }
    }

    private func fetchActiveManualAccounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.isActive && $0.dataSource == .manual }
    }

    private func fetchAllActiveAccounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter(\.isActive)
    }

    private func fetchAsset(coinGeckoId: String) -> Asset? {
        let descriptor = FetchDescriptor<Asset>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { $0.coinGeckoId == coinGeckoId }
    }

    private func fetchAsset(chain: Chain, contract: String) -> Asset? {
        let descriptor = FetchDescriptor<Asset>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { $0.upsertChain == chain && $0.upsertContract == contract }
    }

    private func fetchAsset(sourceKey: String) -> Asset? {
        let descriptor = FetchDescriptor<Asset>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.first { $0.sourceKey == sourceKey }
    }
}

private struct AssetSnapshotAccumulator {
    var accountId: UUID
    var assetId: UUID
    var symbol: String
    var category: AssetCategory
    var grossAmount: Decimal = 0
    var grossUsdValue: Decimal = 0
    var borrowAmount: Decimal = 0
    var borrowUsdValue: Decimal = 0
}

enum SyncError: Error, LocalizedError, Equatable {
    case missingAPIKey(String)
    case noActiveAccounts
    case allAccountsFailed

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(msg): msg
        case .noActiveAccounts: "No active accounts"
        case .allAccountsFailed: "All accounts failed to sync"
        }
    }
}
