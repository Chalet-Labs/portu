import Foundation
import SwiftData
import PortuCore
import PortuNetwork

@MainActor
final class SyncEngine {
    private let modelContext: ModelContext
    private let appState: AppState
    private let providerFactory: ProviderFactory
    private let snapshotStore: SnapshotStore

    init(
        modelContext: ModelContext,
        appState: AppState,
        providerFactory: ProviderFactory = ProviderFactory(),
        snapshotStore: SnapshotStore = SnapshotStore()
    ) {
        self.modelContext = modelContext
        self.appState = appState
        self.providerFactory = providerFactory
        self.snapshotStore = snapshotStore
    }

    func syncAllAccounts() async throws {
        let allAccounts = try modelContext.fetch(FetchDescriptor<Account>())
        let activeAccounts = allAccounts.filter(\.isActive)
        let remoteAccounts = activeAccounts.filter { $0.dataSource != .manual }
        let hasActiveManualAccounts = activeAccounts.contains { $0.dataSource == .manual }

        guard !activeAccounts.isEmpty else {
            appState.connectionStatus = .idle
            appState.syncStatus = .idle
            return
        }

        appState.connectionStatus = .fetching
        appState.syncStatus = remoteAccounts.isEmpty ? .idle : .syncing(progress: 0)

        var assetCache = try modelContext.fetch(FetchDescriptor<Asset>())
        var failedAccountNames: [String] = []

        for (index, account) in remoteAccounts.enumerated() {
            let context = syncContext(for: account)

            do {
                let provider = try providerFactory.makeProvider(dataSource: account.dataSource, context: context)
                let balances = try await provider.fetchBalances(context: context)
                let defiPositions = try await provider.fetchDeFiPositions(context: context)
                try replacePositions(
                    for: account,
                    with: balances + defiPositions,
                    assetCache: &assetCache
                )
                account.lastSyncedAt = .now
                account.lastSyncError = nil
                try modelContext.save()
            } catch {
                account.lastSyncError = syncErrorMessage(for: error)
                failedAccountNames.append(account.name)
                try modelContext.save()
            }

            let progress = Double(index + 1) / Double(remoteAccounts.count)
            appState.syncStatus = .syncing(progress: progress)
        }

        if !remoteAccounts.isEmpty,
           failedAccountNames.count == remoteAccounts.count,
           !hasActiveManualAccounts {
            let message = "All accounts failed to sync"
            appState.connectionStatus = .error(message)
            appState.syncStatus = .error(message)
            return
        }

        try createSnapshots(
            for: activeAccounts,
            failedAccountNames: Set(failedAccountNames)
        )

        appState.connectionStatus = .idle
        appState.syncStatus = failedAccountNames.isEmpty
            ? .idle
            : .completedWithErrors(failedAccounts: failedAccountNames)
    }

    private func syncContext(for account: Account) -> SyncContext {
        SyncContext(
            accountId: account.id,
            kind: account.kind,
            addresses: account.addresses.map { (address: $0.address, chain: $0.chain) },
            exchangeType: account.exchangeType
        )
    }

    private func replacePositions(
        for account: Account,
        with positionDTOs: [PositionDTO],
        assetCache: inout [Asset]
    ) throws {
        let existingPositions = account.positions
        for position in existingPositions {
            modelContext.delete(position)
        }

        var positions: [Position] = []
        positions.reserveCapacity(positionDTOs.count)

        for dto in positionDTOs {
            let position = Position(
                positionType: dto.positionType,
                netUSDValue: netUSDValue(for: dto.tokens),
                chain: dto.chain,
                protocolId: dto.protocolId,
                protocolName: dto.protocolName,
                protocolLogoURL: dto.protocolLogoURL,
                healthFactor: dto.healthFactor,
                account: account,
                syncedAt: .now
            )

            var tokens: [PositionToken] = []
            tokens.reserveCapacity(dto.tokens.count)
            for tokenDTO in dto.tokens {
                let token = PositionToken(
                    role: tokenDTO.role,
                    amount: tokenDTO.amount,
                    usdValue: tokenDTO.usdValue,
                    asset: resolveAsset(for: tokenDTO, assetCache: &assetCache),
                    position: position
                )
                tokens.append(token)
            }
            position.tokens = tokens

            positions.append(position)
        }

        account.positions = positions
    }

    private func resolveAsset(
        for token: TokenDTO,
        assetCache: inout [Asset]
    ) -> Asset {
        if let coinGeckoId = token.coinGeckoId,
           let existing = assetCache.first(where: { $0.coinGeckoId == coinGeckoId }) {
            mergeMetadata(from: token, into: existing)
            return existing
        }

        if token.coinGeckoId == nil,
           let chain = token.chain,
           let contractAddress = token.contractAddress,
           let existing = assetCache.first(where: {
               $0.upsertChain == chain && $0.upsertContract == contractAddress
           }) {
            mergeMetadata(from: token, into: existing)
            return existing
        }

        if token.coinGeckoId == nil,
           token.contractAddress == nil,
           let sourceKey = token.sourceKey,
           let existing = assetCache.first(where: { $0.sourceKey == sourceKey }) {
            mergeMetadata(from: token, into: existing)
            return existing
        }

        let asset = Asset(
            symbol: token.symbol,
            name: token.name,
            coinGeckoId: token.coinGeckoId,
            upsertChain: token.coinGeckoId == nil ? token.chain : nil,
            upsertContract: token.coinGeckoId == nil ? token.contractAddress : nil,
            sourceKey: token.sourceKey,
            debankId: token.debankId,
            logoURL: token.logoURL,
            category: token.category,
            isVerified: token.isVerified
        )
        modelContext.insert(asset)
        assetCache.append(asset)
        return asset
    }

    private func mergeMetadata(from token: TokenDTO, into asset: Asset) {
        asset.symbol = token.symbol
        asset.name = token.name
        asset.logoURL = token.logoURL
        asset.category = token.category
        asset.isVerified = asset.isVerified || token.isVerified

        if asset.coinGeckoId == nil {
            asset.coinGeckoId = token.coinGeckoId
        }
        if asset.upsertChain == nil, asset.coinGeckoId == nil {
            asset.upsertChain = token.chain
        }
        if asset.upsertContract == nil, asset.coinGeckoId == nil {
            asset.upsertContract = token.contractAddress
        }
        if asset.sourceKey == nil {
            asset.sourceKey = token.sourceKey
        }
        if asset.debankId == nil {
            asset.debankId = token.debankId
        }
    }

    private func createSnapshots(
        for activeAccounts: [Account],
        failedAccountNames: Set<String>
    ) throws {
        let now = Date.now
        let batchID = UUID()
        let activePositions = activeAccounts.flatMap(\.positions)

        let portfolioSnapshot = PortfolioSnapshot(
            syncBatchId: batchID,
            timestamp: now,
            totalValue: activePositions.reduce(0) { $0 + $1.netUSDValue },
            idleValue: totalIdleValue(for: activePositions),
            deployedValue: totalDeployedValue(for: activePositions),
            debtValue: totalDebtValue(for: activePositions),
            isPartial: !failedAccountNames.isEmpty
        )
        modelContext.insert(portfolioSnapshot)

        for account in activeAccounts {
            modelContext.insert(
                AccountSnapshot(
                    syncBatchId: batchID,
                    timestamp: now,
                    accountId: account.id,
                    totalValue: account.positions.reduce(0) { $0 + $1.netUSDValue },
                    isFresh: !failedAccountNames.contains(account.name)
                )
            )
        }

        for account in activeAccounts {
            let groupedTokens = Dictionary(
                grouping: account.positions.flatMap(\.tokens).compactMap { token -> (UUID, PositionToken)? in
                    guard let assetID = token.asset?.id else { return nil }
                    return (assetID, token)
                },
                by: \.0
            )

            for tokens in groupedTokens.values {
                guard let firstToken = tokens.first?.1,
                      let asset = firstToken.asset
                else {
                    continue
                }

                let snapshot = AssetSnapshot(
                    syncBatchId: batchID,
                    timestamp: now,
                    accountId: account.id,
                    assetId: asset.id,
                    symbol: asset.symbol,
                    category: asset.category,
                    amount: tokens.reduce(0) { $0 + positiveAmount(for: $1.1) },
                    usdValue: tokens.reduce(0) { $0 + positiveUSDValue(for: $1.1) },
                    borrowAmount: tokens.reduce(0) { $0 + borrowAmount(for: $1.1) },
                    borrowUsdValue: tokens.reduce(0) { $0 + borrowUSDValue(for: $1.1) }
                )
                modelContext.insert(snapshot)
            }
        }

        try pruneSnapshots(now: now)
        try modelContext.save()
    }

    private func pruneSnapshots(now: Date) throws {
        let portfolioSnapshots = try modelContext.fetch(FetchDescriptor<PortfolioSnapshot>())
        let accountSnapshots = try modelContext.fetch(FetchDescriptor<AccountSnapshot>())
        let assetSnapshots = try modelContext.fetch(FetchDescriptor<AssetSnapshot>())

        let retainedPortfolioDates = snapshotStore.prune(
            snapshotDates: portfolioSnapshots.map(\.timestamp),
            now: now
        )
        let retainedAccountDates = snapshotStore.prune(
            snapshotDates: accountSnapshots.map(\.timestamp),
            now: now
        )
        let retainedAssetDates = snapshotStore.prune(
            snapshotDates: assetSnapshots.map(\.timestamp),
            now: now
        )

        for snapshot in portfolioSnapshots where !retainedPortfolioDates.contains(snapshot.timestamp) {
            modelContext.delete(snapshot)
        }
        for snapshot in accountSnapshots where !retainedAccountDates.contains(snapshot.timestamp) {
            modelContext.delete(snapshot)
        }
        for snapshot in assetSnapshots where !retainedAssetDates.contains(snapshot.timestamp) {
            modelContext.delete(snapshot)
        }
    }

    private func netUSDValue(for tokens: [TokenDTO]) -> Decimal {
        tokens.reduce(0) { partial, token in
            partial + signedUSDValue(for: token.role, absoluteValue: token.usdValue)
        }
    }

    private func totalIdleValue(for positions: [Position]) -> Decimal {
        positions
            .filter { $0.positionType == .idle }
            .reduce(0) { partial, position in
                partial + position.tokens.reduce(0) { $0 + positiveUSDValue(for: $1) }
            }
    }

    private func totalDeployedValue(for positions: [Position]) -> Decimal {
        positions
            .filter { $0.positionType != .idle }
            .reduce(0) { partial, position in
                partial + position.tokens.reduce(0) { $0 + positiveUSDValue(for: $1) }
            }
    }

    private func totalDebtValue(for positions: [Position]) -> Decimal {
        positions.reduce(0) { partial, position in
            partial + position.tokens.reduce(0) { $0 + borrowUSDValue(for: $1) }
        }
    }

    private func positiveAmount(for token: PositionToken) -> Decimal {
        switch token.role {
        case .balance, .supply, .stake, .lpToken:
            return token.amount
        case .borrow, .reward:
            return 0
        }
    }

    private func positiveUSDValue(for token: PositionToken) -> Decimal {
        switch token.role {
        case .balance, .supply, .stake, .lpToken:
            return token.usdValue
        case .borrow, .reward:
            return 0
        }
    }

    private func borrowAmount(for token: PositionToken) -> Decimal {
        token.role == .borrow ? token.amount : 0
    }

    private func borrowUSDValue(for token: PositionToken) -> Decimal {
        token.role == .borrow ? token.usdValue : 0
    }

    private func signedUSDValue(for role: TokenRole, absoluteValue: Decimal) -> Decimal {
        switch role {
        case .balance, .supply, .stake, .lpToken:
            return absoluteValue
        case .borrow:
            return -absoluteValue
        case .reward:
            return 0
        }
    }

    private func syncErrorMessage(for error: any Error) -> String {
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
