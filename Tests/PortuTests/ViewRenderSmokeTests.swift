import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

@MainActor
struct ViewRenderSmokeTests {
    private static var retainedWindows: [NSWindow] = []

    @Test(arguments: [
        SidebarSection.overview,
        .exposure,
        .performance,
        .allAssets,
        .allPositions,
        .accounts
    ])
    func `dashboard section renders without crashing`(_ section: SidebarSection) throws {
        let container = try makeContainer()
        let store = makeStore(section: section)
        let appState = AppState()
        appState.bridge(from: store)

        let view = ContentView(store: store)
            .modelContainer(container)
            .environment(appState)
            .frame(width: 1400, height: 900)

        render(view)
    }

    @Test(arguments: AssetTab.allCases)
    func `all assets tabs render without crashing`(_ tab: AssetTab) throws {
        let container = try makeContainer()
        var state = populatedState(section: .allAssets)
        state.allAssets.selectedTab = tab
        let store = makeStore(state: state)
        let appState = AppState()
        appState.bridge(from: store)

        let view = ContentView(store: store)
            .modelContainer(container)
            .environment(appState)
            .frame(width: 1400, height: 900)

        render(view)
    }

    @Test func `asset detail renders without crashing`() throws {
        let container = try makeContainer()
        let asset = try #require(try container.mainContext.fetch(FetchDescriptor<Asset>()).first)
        let store = makeStore(section: .allAssets)

        let view = AssetDetailView(assetId: asset.id, store: store)
            .modelContainer(container)
            .frame(width: 1400, height: 900)

        render(view)
    }

    @Test func `settings route renders without crashing`() throws {
        let container = try makeContainer()
        var state = populatedState(section: .overview)
        state.isSettingsPresented = true
        let store = makeStore(state: state)
        let appState = AppState()
        appState.bridge(from: store)

        let view = ContentView(store: store)
            .modelContainer(container)
            .environment(appState)
            .frame(width: 1400, height: 900)

        render(view)
    }

    @Test func `add account sheet renders without crashing`() throws {
        let container = try makeContainer()

        let view = AddAccountSheet()
            .modelContainer(container)
            .environment(\.colorScheme, .dark)
            .frame(width: 920, height: 760)

        render(view)
    }

    private func makeStore(section: SidebarSection) -> StoreOf<AppFeature> {
        makeStore(state: populatedState(section: section))
    }

    private func makeStore(state: AppFeature.State) -> StoreOf<AppFeature> {
        Store(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = { SyncResult(failedAccounts: []) }
            $0.priceService.fetchPrices = { _ in PriceUpdate(prices: [:], changes24h: [:]) }
            $0.priceService.invalidateCache = {}
        }
    }

    private func populatedState(section: SidebarSection) -> AppFeature.State {
        var state = AppFeature.State(selectedSection: section)
        state.prices = ["ethereum": 3050, "usd-coin": 1]
        state.priceChanges24h = ["ethereum": 0.021, "usd-coin": 0]
        state.lastPriceUpdate = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return state
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Account.self,
            WalletAddress.self,
            Position.self,
            PositionToken.self,
            Asset.self,
            PortfolioSnapshot.self,
            AccountSnapshot.self,
            AssetSnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        try seedSampleData(in: container)
        return container
    }

    private func seedSampleData(in container: ModelContainer) throws {
        let context = container.mainContext
        let ids = SampleIDs()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let assets = makeSampleAssets(ids: ids)
        let account = makeSampleAccount(id: ids.account, now: now, assets: assets)

        context.insert(assets.eth)
        context.insert(assets.usdc)
        context.insert(account)
        insertSnapshots(context: context, ids: ids, now: now)

        try context.save()
    }

    private func makeSampleAssets(ids: SampleIDs) -> (eth: Asset, usdc: Asset) {
        let eth = Asset(
            id: ids.eth,
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major,
            isVerified: true)
        let usdc = Asset(
            id: ids.usdc,
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true)
        return (eth, usdc)
    }

    private func makeSampleAccount(
        id: UUID,
        now: Date,
        assets: (eth: Asset, usdc: Asset)) -> Account {
        let account = Account(
            id: id,
            name: "Primary Wallet",
            kind: .wallet,
            dataSource: .zapper,
            lastSyncedAt: now)
        let ethToken = PositionToken(role: .balance, amount: 2, usdValue: 6000, asset: assets.eth)
        let usdcToken = PositionToken(role: .supply, amount: 4000, usdValue: 4000, asset: assets.usdc)
        let borrowToken = PositionToken(role: .borrow, amount: 500, usdValue: 500, asset: assets.usdc)

        account.positions = [
            Position(
                positionType: .idle,
                chain: .ethereum,
                netUSDValue: 6000,
                tokens: [ethToken],
                account: account,
                syncedAt: now),
            Position(
                positionType: .lending,
                chain: .ethereum,
                protocolId: "aave-v3",
                protocolName: "Aave V3",
                healthFactor: 2.4,
                netUSDValue: 3500,
                tokens: [usdcToken, borrowToken],
                account: account,
                syncedAt: now)
        ]
        return account
    }

    private func insertSnapshots(context: ModelContext, ids: SampleIDs, now: Date) {
        for day in 0 ..< 5 {
            let timestamp = now.addingTimeInterval(Double(day - 4) * 86400)
            let total = Decimal(8600 + day * 240)
            context.insert(PortfolioSnapshot(
                syncBatchId: ids.batch,
                timestamp: timestamp,
                totalValue: total,
                idleValue: total * Decimal(60) / Decimal(100),
                deployedValue: total * Decimal(40) / Decimal(100),
                debtValue: 500,
                isPartial: false))
            context.insert(AccountSnapshot(
                syncBatchId: ids.batch,
                timestamp: timestamp,
                accountId: ids.account,
                totalValue: total,
                isFresh: true))
            context.insert(AssetSnapshot(
                syncBatchId: ids.batch,
                timestamp: timestamp,
                accountId: ids.account,
                assetId: ids.eth,
                symbol: "ETH",
                category: .major,
                amount: 2,
                usdValue: 6000))
            context.insert(AssetSnapshot(
                syncBatchId: ids.batch,
                timestamp: timestamp,
                accountId: ids.account,
                assetId: ids.usdc,
                symbol: "USDC",
                category: .stablecoin,
                amount: 4000,
                usdValue: 4000,
                borrowAmount: 500,
                borrowUsdValue: 500))
        }
    }

    private struct SampleIDs {
        let account = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let eth = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let usdc = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let batch = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    }

    private func render(_ view: some View) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 1400, height: 900)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        Self.retainedWindows.append(window)
    }
}
