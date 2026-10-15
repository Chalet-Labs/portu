import Foundation
@testable import Portu
import PortuCore
import PortuNetwork
import SwiftData
import Testing

/// Snapshot recording through a whole sync (spec N1, N3, T3). Manual accounts keep their
/// positions across a sync, so a stored `netUSDValue` that disagrees with its tokens survives into
/// the snapshot step; a failing provider does the same for a wallet's kept positions.
@MainActor
struct SyncEngineIgnoredSnapshotTests {
    private static let pending: Comment = "Snapshot recording leaves ignored assets out in the next commit"

    private struct Recorded {
        let portfolio: PortfolioSnapshot
        let accounts: [UUID: AccountSnapshot]
        let assets: [AssetSnapshot]
    }

    private func makeContext() throws -> ModelContext {
        try ModelContext(ModelContainerFactory().makeInMemory())
    }

    private func makeEngine(
        _ context: ModelContext,
        failing failedID: UUID? = nil,
        balances: [PositionDTO] = []) -> SyncEngine {
        SyncEngine(modelContext: context, providerFactory: ProviderFactory(resolver: { _, syncContext in
            if syncContext.accountId == failedID {
                throw IgnoredSnapshotTestError.forcedProviderFailure
            }
            return IgnoredSnapshotStubProvider(balances: balances)
        }))
    }

    private func manualAccount(
        _ name: String,
        positions: [Position],
        isActive: Bool = true) -> Account {
        Account(name: name, kind: .manual, dataSource: .manual, positions: positions, isActive: isActive)
    }

    /// The rows of the most recent batch.
    private func latestBatch(in context: ModelContext) throws -> Recorded {
        let portfolio = try #require(
            try context.fetch(FetchDescriptor<PortfolioSnapshot>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)])).first)
        let batchId = portfolio.syncBatchId
        let accounts = try context.fetch(FetchDescriptor<AccountSnapshot>(
            predicate: #Predicate { $0.syncBatchId == batchId }))
        let assets = try context.fetch(FetchDescriptor<AssetSnapshot>(
            predicate: #Predicate { $0.syncBatchId == batchId }))
        return Recorded(
            portfolio: portfolio,
            accounts: Dictionary(accounts.map { ($0.accountId, $0) }, uniquingKeysWith: { first, _ in first }),
            assets: assets)
    }

    // MARK: - N1 recording

    @Test func `a sync leaves ignored assets out of the portfolio, account and asset snapshots`() async throws {
        let context = try makeContext()
        let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        let scam = Asset(symbol: "SCAM", name: "Scam", category: .other)
        let main = manualAccount("Main", positions: [
            Position(positionType: .idle, netUSDValue: 3500, tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 3000, asset: eth),
                PositionToken(role: .balance, amount: 1000, usdValue: 500, asset: scam)
            ])
        ])
        let scamOnly = manualAccount("Airdrops", positions: [
            Position(positionType: .idle, netUSDValue: 200, tokens: [
                PositionToken(role: .balance, amount: 400, usdValue: 200, asset: scam)
            ])
        ])
        context.insert(main)
        context.insert(scamOnly)
        context.insert(TokenPricingOverride(assetId: scam.id, isIgnored: true))
        try context.save()

        _ = try await makeEngine(context).sync()

        let recorded = try latestBatch(in: context)
        let mainRow = try #require(recorded.accounts[main.id])
        let scamOnlyRow = try #require(recorded.accounts[scamOnly.id], "An account whose tokens are all ignored still records a row")
        #expect(recorded.accounts.count == 2)
        #expect(recorded.assets.contains { $0.assetId == eth.id })
        withKnownIssue(Self.pending) {
            #expect(recorded.portfolio.totalValue == 3000)
            #expect(recorded.portfolio.idleValue == 3000)
            #expect(mainRow.totalValue == 3000)
            #expect(scamOnlyRow.totalValue == 0)
            #expect(!recorded.assets.contains { $0.assetId == scam.id })
        }
    }

    /// Positions by type, with the hand-checked split: idle 1000; lending supply 500 against a
    /// 200 borrow; vesting 300; other 100; a farming position holding only a 50 reward, which
    /// counts nowhere. The stored totals match their tokens, so only the deployed split moves.
    @Test func `deployed includes vesting and other, and idle plus deployed minus debt is the total`() async throws {
        let context = try makeContext()
        func asset(_ symbol: String) -> Asset {
            Asset(symbol: symbol, name: symbol, category: .other)
        }
        let account = manualAccount("Main", positions: [
            Position(positionType: .idle, netUSDValue: 1000, tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 1000, asset: asset("ETH"))
            ]),
            Position(positionType: .lending, netUSDValue: 300, tokens: [
                PositionToken(role: .supply, amount: 500, usdValue: 500, asset: asset("USDC")),
                PositionToken(role: .borrow, amount: 200, usdValue: 200, asset: asset("DAI"))
            ]),
            Position(positionType: .vesting, netUSDValue: 300, tokens: [
                PositionToken(role: .balance, amount: 30, usdValue: 300, asset: asset("VEST"))
            ]),
            Position(positionType: .other, netUSDValue: 100, tokens: [
                PositionToken(role: .balance, amount: 10, usdValue: 100, asset: asset("MISC"))
            ]),
            Position(positionType: .farming, netUSDValue: 0, tokens: [
                PositionToken(role: .reward, amount: 5, usdValue: 50, asset: asset("RWD"))
            ])
        ])
        context.insert(account)
        try context.save()

        _ = try await makeEngine(context).sync()

        let portfolio = try latestBatch(in: context).portfolio
        #expect(portfolio.totalValue == 1700)
        #expect(portfolio.idleValue == 1000)
        #expect(portfolio.debtValue == 200)
        withKnownIssue(Self.pending) {
            // N1 / A3: vesting and other land in deployed.
            #expect(portfolio.deployedValue == 900)
            #expect(portfolio.idleValue + portfolio.deployedValue - portfolio.debtValue == portfolio.totalValue)
        }
    }

    /// Sync rewrites `netUSDValue` for every account it refreshes, so the divergence sits on
    /// positions the run keeps: a manual account's, and a wallet's whose provider fails.
    @Test func `the recorded total follows the tokens, not the stored position total`() async throws {
        let context = try makeContext()
        let eth = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        let old = Asset(symbol: "OLD", name: "Old Token", category: .other)
        let manual = manualAccount("Manual", positions: [
            Position(positionType: .idle, netUSDValue: 9999, tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 3000, asset: eth)
            ])
        ])
        let failed = Account(name: "Failed", kind: .wallet, dataSource: .zerion)
        failed.addresses = [WalletAddress(address: "0xfailed", account: failed)]
        failed.positions = [
            Position(positionType: .idle, chain: .ethereum, netUSDValue: 777, tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 100, asset: old)
            ])
        ]
        context.insert(manual)
        context.insert(failed)
        try context.save()

        let result = try await makeEngine(context, failing: failed.id).sync()

        #expect(result.failedAccounts == ["Failed"])
        let recorded = try latestBatch(in: context)
        let manualRow = try #require(recorded.accounts[manual.id])
        let failedRow = try #require(recorded.accounts[failed.id], "The failed account's kept positions feed the snapshot")
        #expect(failedRow.isFresh == false)
        #expect(recorded.portfolio.isPartial == true)
        withKnownIssue(Self.pending) {
            #expect(recorded.portfolio.totalValue == 3100)
            #expect(manualRow.totalValue == 3000)
            #expect(failedRow.totalValue == 100)
        }
    }

    /// Three syncs: before the ignore, while ignored, after un-ignoring. Asset Detail's chart
    /// reads `AssetSnapshot` by `assetId` with no ignore filter (S7), so the missing middle row
    /// is the gap it shows after an un-ignore; the earlier row is still there (N3).
    @Test func `un-ignoring an asset records it again on the next sync`() async throws {
        let context = try makeContext()
        let eth = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        let scam = Asset(symbol: "SCAM", name: "Scam", category: .other)
        let account = manualAccount("Main", positions: [
            Position(positionType: .idle, netUSDValue: 3500, tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 3000, asset: eth),
                PositionToken(role: .balance, amount: 1000, usdValue: 500, asset: scam)
            ])
        ])
        context.insert(account)
        try context.save()
        let engine = makeEngine(context)
        let scamID = scam.id
        let scamRows = FetchDescriptor<AssetSnapshot>(
            predicate: #Predicate { $0.assetId == scamID },
            sortBy: [SortDescriptor(\.timestamp)])

        _ = try await engine.sync()
        let before = try latestBatch(in: context)
        #expect(before.portfolio.totalValue == 3500)
        #expect(before.assets.contains { $0.assetId == scamID })

        let override = TokenPricingOverride(assetId: scamID, isIgnored: true)
        context.insert(override)
        try context.save()
        _ = try await engine.sync()
        let ignored = try latestBatch(in: context)
        try #require(ignored.portfolio.syncBatchId != before.portfolio.syncBatchId)
        withKnownIssue(Self.pending) {
            #expect(ignored.portfolio.totalValue == 3000)
            #expect(!ignored.assets.contains { $0.assetId == scamID })
        }

        override.isIgnored = false
        try context.save()
        _ = try await engine.sync()
        let restored = try latestBatch(in: context)
        try #require(restored.portfolio.syncBatchId != ignored.portfolio.syncBatchId)
        #expect(restored.portfolio.totalValue == 3500)
        #expect(restored.assets.contains { $0.assetId == scamID })

        let batches = try context.fetch(scamRows).map(\.syncBatchId)
        #expect(batches.first == before.portfolio.syncBatchId)
        #expect(batches.last == restored.portfolio.syncBatchId)
        withKnownIssue(Self.pending) {
            #expect(batches == [before.portfolio.syncBatchId, restored.portfolio.syncBatchId])
        }
    }

    // MARK: - Guards (green before and after)

    @Test func `existing portfolio, account and asset rows are not rewritten`() async throws {
        let context = try makeContext()
        let scam = Asset(symbol: "SCAM", name: "Scam", category: .other)
        let account = manualAccount("Main", positions: [
            Position(positionType: .idle, netUSDValue: 500, tokens: [
                PositionToken(role: .balance, amount: 1000, usdValue: 500, asset: scam)
            ])
        ])
        context.insert(account)
        let oldBatch = UUID()
        let oldTimestamp = Date.now.addingTimeInterval(-3600)
        context.insert(PortfolioSnapshot(
            syncBatchId: oldBatch, timestamp: oldTimestamp,
            totalValue: 12345, idleValue: 12000, deployedValue: 345, debtValue: 0, isPartial: false))
        context.insert(AccountSnapshot(
            syncBatchId: oldBatch, timestamp: oldTimestamp,
            accountId: account.id, totalValue: 12345, isFresh: true))
        context.insert(AssetSnapshot(
            syncBatchId: oldBatch, timestamp: oldTimestamp,
            accountId: account.id, assetId: scam.id, symbol: "SCAM",
            category: .other, amount: 1000, usdValue: 500))
        context.insert(TokenPricingOverride(assetId: scam.id, isIgnored: true))
        try context.save()

        _ = try await makeEngine(context).sync()

        let portfolio = try context.fetch(FetchDescriptor<PortfolioSnapshot>(
            predicate: #Predicate { $0.syncBatchId == oldBatch }))
        let accounts = try context.fetch(FetchDescriptor<AccountSnapshot>(
            predicate: #Predicate { $0.syncBatchId == oldBatch }))
        let assets = try context.fetch(FetchDescriptor<AssetSnapshot>(
            predicate: #Predicate { $0.syncBatchId == oldBatch }))
        #expect(portfolio.map(\.totalValue) == [12345])
        #expect(portfolio.map(\.idleValue) == [12000])
        #expect(portfolio.map(\.deployedValue) == [345])
        #expect(accounts.map(\.totalValue) == [12345])
        #expect(assets.map(\.usdValue) == [500])
    }

    /// The freshness rules N1 keeps: a failed wallet's kept positions stay in the totals with
    /// `isFresh == false`, its asset rows are skipped, and the batch is partial. An unrelated
    /// ignore makes the override path run without touching these numbers.
    @Test func `partial-sync and stale-account freshness handling is unchanged`() async throws {
        let context = try makeContext()
        let succeeded = Account(name: "Succeeded", kind: .wallet, dataSource: .zerion)
        succeeded.addresses = [WalletAddress(address: "0xsucceeded", account: succeeded)]
        let old = Asset(symbol: "OLD", name: "Old Token", category: .major)
        let failed = Account(name: "Failed", kind: .wallet, dataSource: .zerion)
        failed.addresses = [WalletAddress(address: "0xfailed", account: failed)]
        failed.positions = [
            Position(positionType: .idle, chain: .ethereum, netUSDValue: 100, tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 100, asset: old)
            ])
        ]
        let manual = manualAccount("Manual", positions: [
            Position(positionType: .idle, netUSDValue: 40, tokens: [
                PositionToken(role: .balance, amount: 2, usdValue: 40, asset: Asset(symbol: "CASH", name: "Cash", category: .stablecoin))
            ])
        ])
        context.insert(succeeded)
        context.insert(failed)
        context.insert(manual)
        context.insert(TokenPricingOverride(assetId: UUID(), isIgnored: true))
        try context.save()
        let engine = makeEngine(context, failing: failed.id, balances: [
            PositionDTO(
                positionType: .idle,
                chain: .ethereum,
                protocolId: nil,
                protocolName: nil,
                protocolLogoURL: nil,
                healthFactor: nil,
                tokens: [makeTokenDTO(symbol: "ETH", usdValue: 250)])
        ])

        let result = try await engine.sync()

        #expect(result.failedAccounts == ["Failed"])
        let recorded = try latestBatch(in: context)
        #expect(recorded.portfolio.isPartial == true)
        #expect(recorded.portfolio.totalValue == 390)
        #expect(recorded.accounts[succeeded.id]?.isFresh == true)
        #expect(recorded.accounts[succeeded.id]?.totalValue == 250)
        #expect(recorded.accounts[failed.id]?.isFresh == false)
        #expect(recorded.accounts[failed.id]?.totalValue == 100)
        #expect(recorded.accounts[manual.id]?.isFresh == true)
        #expect(recorded.accounts[manual.id]?.totalValue == 40)
        #expect(!recorded.assets.contains { $0.accountId == failed.id })
        #expect(Set(recorded.assets.map(\.accountId)) == [succeeded.id, manual.id])
    }

    @Test func `an inactive account's tokens stay out of every snapshot`() async throws {
        let context = try makeContext()
        let eth = Asset(symbol: "ETH", name: "Ethereum", category: .major)
        let btc = Asset(symbol: "BTC", name: "Bitcoin", category: .major)
        let active = manualAccount("Active", positions: [
            Position(positionType: .idle, netUSDValue: 3000, tokens: [
                PositionToken(role: .balance, amount: 1, usdValue: 3000, asset: eth)
            ])
        ])
        let inactive = manualAccount("Inactive", positions: [
            Position(positionType: .lending, netUSDValue: 5000, tokens: [
                PositionToken(role: .supply, amount: 0.1, usdValue: 5000, asset: btc)
            ])
        ], isActive: false)
        context.insert(active)
        context.insert(inactive)
        try context.save()

        _ = try await makeEngine(context).sync()

        let recorded = try latestBatch(in: context)
        #expect(recorded.portfolio.totalValue == 3000)
        #expect(recorded.portfolio.deployedValue == 0)
        #expect(Array(recorded.accounts.keys) == [active.id])
        #expect(!recorded.assets.contains { $0.assetId == btc.id })
    }

    private func makeTokenDTO(symbol: String, usdValue: Decimal) -> TokenDTO {
        TokenDTO(
            role: .balance,
            symbol: symbol,
            name: symbol,
            amount: 1,
            usdValue: usdValue,
            chain: nil,
            contractAddress: nil,
            debankId: nil,
            coinGeckoId: nil,
            sourceKey: nil,
            logoURL: nil,
            category: .other,
            isVerified: false)
    }
}

private actor IgnoredSnapshotStubProvider: PortfolioDataProvider {
    nonisolated var capabilities: ProviderCapabilities {
        ProviderCapabilities()
    }

    let balances: [PositionDTO]

    init(balances: [PositionDTO]) {
        self.balances = balances
    }

    func fetchBalances(context _: SyncContext) async throws -> [PositionDTO] {
        balances
    }
}

private enum IgnoredSnapshotTestError: Error {
    case forcedProviderFailure
}
