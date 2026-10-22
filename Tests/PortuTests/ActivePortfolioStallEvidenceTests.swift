import Foundation
@testable import Portu
import PortuCore
import SwiftData
import Testing

/// Evidence for U8, not a gate: the main-thread CPU of one dashboard body pass on All Positions
/// after a sync-like save, in the shape before C-P (the header and the page each fetch and walk
/// the store) and after it (one fetch and one projection, valued by both). Every step runs
/// synchronously on the main actor, so the test host's own dashboard cannot interleave. The test
/// asserts only that both shapes show the same numbers; the timings are printed as "C-P timing:".
@MainActor
struct ActivePortfolioStallEvidenceTests {
    private static let rounds = 3
    private static let positionsPerAccount = [160, 160, 80]
    private static let tokensPerPosition = 4
    private static let assetCount = 150

    private struct Pass: Equatable {
        let headline: OverviewHeadline
        let page: AllPositionsPage
    }

    @Test func `one shared projection values the header and the page as two walks did`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ActivePortfolioStallEvidenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainerFactory(storeURL: directory.appending(path: "Portu.store")).makeForProduction()
        let context = container.mainContext
        let (accounts, assets) = try Self.seed(context)
        let appState = AppState()
        appState.livePricesUSD = Dictionary(uniqueKeysWithValues: assets.enumerated().compactMap { index, asset in
            index.isMultiple(of: 3) ? nil : asset.coinGeckoId.map { ($0, Decimal(index + 1)) }
        })

        var timesA: [Double] = []
        var timesB: [Double] = []
        for round in 0 ... Self.rounds {
            try Self.resync(accounts[round % 2], assets: assets, in: context)
            // The shape that runs first alternates per round.
            var passes: [Bool: (pass: Pass, milliseconds: Double)] = [:]
            for isShared in round.isMultiple(of: 2) ? [false, true] : [true, false] {
                let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                let pass = try isShared ? Self.oneProjection(context, appState: appState) : Self.twoWalks(context, appState: appState)
                passes[isShared] = (pass, Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000)
            }
            let shapeA = try #require(passes[false])
            let shapeB = try #require(passes[true])

            #expect(shapeA.pass == shapeB.pass, "round \(round)")
            #expect(!shapeA.pass.page.sections.isEmpty)
            guard round > 0 else { continue }
            timesA.append(shapeA.milliseconds)
            timesB.append(shapeB.milliseconds)
        }

        let tokens = Self.positionsPerAccount.reduce(0, +) * Self.tokensPerPosition
        print("C-P timing: store \(Self.positionsPerAccount.reduce(0, +)) positions, \(tokens) tokens, \(Self.assetCount) assets, 1 inactive account")
        print("C-P timing: shape A (two fetches and walks) cpu-ms runs=\(Self.format(timesA)) median=\(Self.format([Self.median(timesA)]))")
        print("C-P timing: shape B (one fetch, one projection) cpu-ms runs=\(Self.format(timesB)) median=\(Self.format([Self.median(timesB)]))")
    }

    /// The branch before C-P: the header values the active accounts' tokens over its own fetch, and the
    /// page builds its projection over another.
    private static func twoWalks(_ context: ModelContext, appState: AppState) throws -> Pass {
        let headerPositions = try context.fetch(FetchDescriptor<Position>())
        let headline = OverviewFeature.headline(.activeAccounts(
            headerPositions.filter { $0.account?.isActive == true }.flatMap(\.tokens),
            overrides: [],
            mappings: [],
            settings: .defaults,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: .live(appState, historical: .empty, includingLiveChanges: true)))
        let pagePositions = try context.fetch(FetchDescriptor<Position>())
        let projection = ActivePortfolioProjection(pagePositions)
        let page = AllPositionsFeature.page(
            valuation(projection, appState: appState, includingLiveChanges: false),
            cards: projection.cards,
            filter: .all)
        return Pass(headline: headline, page: page)
    }

    /// C-P: one fetch and one projection, valued by the header and the page.
    private static func oneProjection(_ context: ModelContext, appState: AppState) throws -> Pass {
        let projection = try ActivePortfolioProjection(context.fetch(FetchDescriptor<Position>()))
        let headline = OverviewFeature.headline(valuation(projection, appState: appState, includingLiveChanges: true))
        let page = AllPositionsFeature.page(
            valuation(projection, appState: appState, includingLiveChanges: false),
            cards: projection.cards,
            filter: .all)
        return Pass(headline: headline, page: page)
    }

    private static func valuation(_ projection: ActivePortfolioProjection, appState: AppState, includingLiveChanges: Bool) -> ValuationContext {
        ValuationContext(
            inputs: projection.inputs,
            overrides: [],
            mappings: [],
            settings: .defaults,
            usdToDisplayRate: appState.currentUSDToDisplayRate,
            prices: .live(appState, historical: .empty, includingLiveChanges: includingLiveChanges))
    }

    private static func seed(_ context: ModelContext) throws -> (accounts: [Account], assets: [Asset]) {
        let assets = (0 ..< assetCount).map { index in
            Asset(symbol: "A\(index)", name: "Asset \(index)", coinGeckoId: "asset-\(index)", category: .other)
        }
        let accounts = positionsPerAccount.indices.map { index in
            Account(name: "Wallet \(index)", kind: .wallet, dataSource: .zerion, isActive: index < 2)
        }
        assets.forEach(context.insert)
        accounts.forEach(context.insert)
        for (account, count) in zip(accounts, positionsPerAccount) {
            insertPositions(count, into: account, assets: assets, offset: 0, in: context)
        }
        try context.save()
        return (accounts, assets)
    }

    /// What a sync does to one account: delete its positions, reinsert them on the same assets, save.
    private static func resync(_ account: Account, assets: [Asset], in context: ModelContext) throws {
        let accountID = account.id
        let positions = try context.fetch(FetchDescriptor<Position>()).filter { $0.account?.id == accountID }
        positions.forEach(context.delete)
        insertPositions(positions.count, into: account, assets: assets, offset: 1, in: context)
        try context.save()
    }

    private static func insertPositions(_ count: Int, into account: Account, assets: [Asset], offset: Int, in context: ModelContext) {
        let types: [PositionType] = [.idle, .lending, .liquidityPool, .staking]
        for index in 0 ..< count {
            let tokens = (0 ..< tokensPerPosition).map { slot in
                let asset = assets[(index * tokensPerPosition + slot + offset) % assets.count]
                return PositionToken(role: slot == 3 ? .borrow : .balance, amount: Decimal(slot + 1), usdValue: Decimal(index + slot), asset: asset)
            }
            context.insert(Position(
                positionType: types[index % types.count],
                chain: .ethereum,
                protocolId: index.isMultiple(of: 2) ? nil : "protocol-\(index % 7)",
                protocolName: index.isMultiple(of: 2) ? nil : "Protocol \(index % 7)",
                tokens: tokens,
                account: account,
                syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func format(_ values: [Double]) -> String {
        "[" + values.map { String(format: "%.1f", $0) }.joined(separator: ", ") + "]"
    }
}
