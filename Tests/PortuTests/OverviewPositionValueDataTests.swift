import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// Guards the contract from issue #103: the `PortfolioProjector` is the only code that reads position
/// models for the Overview (`PortfolioProjection.init`, on its own context), and everything it hands
/// to the UI must remain valid after those models are deleted. `SyncEngine` deletes and reinserts
/// positions on the main actor while SwiftUI may still be evaluating a body, and reading a deleted
/// model's property trips a SwiftData assertion that terminates the process.
@Suite(.serialized)
@MainActor
struct OverviewPositionValueDataTests {
    private static let maxRetainedWindows = 8
    private static var retainedWindows: [NSWindow] = []
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Visibility is permissive so tests exercise projection and grouping, not thresholds.
    private static let permissive = TokenDashboardSettings(minimumDashboardValue: 0, hideUnpriced: false, hideDust: false)
    private static let usdBook = ["usd-coin": Decimal(1), "tether": 1]

    @Test func `projection outlives deletion of its source models`() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedAccount(in: context, positionType: .lending, protocolName: "Aave V3", includeBorrow: true)

        let groups = try await tab(.borrowing, in: container).groups

        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.position.title == "Aave V3")
        #expect(group.tokens.map(\.symbol) == ["USDT"])
        #expect(group.value == 500)

        // What the sync does mid-render: delete the positions this data came from.
        for position in try context.fetch(FetchDescriptor<Position>()) {
            context.delete(position)
        }
        try context.save()

        // Still readable and renderable, because the projection copied everything.
        #expect(group.position.title == "Aave V3")
        #expect(group.position.chain == .ethereum)
        #expect(group.tokens.map(\.symbol) == ["USDT"])
        #expect(group.value == 500)

        render(OverviewPositionGroupCard(group: group, currencyCode: "USD"))
    }

    @Test func `the borrowing group total is its debt as a positive amount`() async throws {
        let container = try makeContainer()
        try seedAccount(in: container.mainContext, positionType: .lending, protocolName: "Aave V3", includeBorrow: true)

        let borrowing = try #require(await tab(.borrowing, in: container).groups.first)
        // Only the borrow leg reaches this tab, and the tab shows debt as a positive amount.
        #expect(borrowing.value == 500)
        #expect(borrowing.basis == .debt)
    }

    @Test func `idle tabs exclude positions that are not idle`() async throws {
        let container = try makeContainer()
        try seedAccount(in: container.mainContext, positionType: .lending, protocolName: "Aave V3", includeBorrow: false)

        #expect(try await tab(.idleStables, in: container).groups.isEmpty)
    }

    @Test func `idle stables tab titles wallet positions by account name`() async throws {
        let container = try makeContainer()
        try seedAccount(in: container.mainContext, positionType: .idle, protocolName: nil, includeBorrow: false)

        let group = try #require(await tab(.idleStables, in: container).groups.first)

        // No protocol name, so the account name is the fallback title.
        #expect(group.position.title == "Primary Wallet")
        #expect(group.tokens.map(\.symbol) == ["USDC"])
        #expect(group.value == 4000)
    }

    @Test func `position tabs offer only tabs backed by position data`() {
        #expect(OverviewPositionTab.allCases == [.keyChanges, .idleStables, .idleMajors, .borrowing])
    }

    /// A smoke, not a proof: the view reads only the values in its store, so deleting the models they
    /// were projected from can't reach it. Kept so a view that took a model again would crash here,
    /// as the 1.9.0 crash (#103) did.
    @Test func `position tabs render from a value store after every position is deleted mid-session`() async throws {
        let container = try makeContainer()
        try seedAccount(
            in: container.mainContext,
            positionType: .idle,
            protocolName: nil,
            includeBorrow: true)
        let revaluation = try await revaluation(of: container)
        let tabs = try #require(revaluation.overview.positionTabs[.borrowing])
        #expect(!tabs.groups.isEmpty, "the view has a group to render")

        let view = OverviewPositionTabs(store: OverviewModelWiringTests.portfolioStore(revaluation))
            .frame(width: 1400, height: 900)

        render(view)

        let context = container.mainContext
        for position in try context.fetch(FetchDescriptor<Position>()) {
            context.delete(position)
        }
        try context.save()

        render(view)
    }

    // MARK: - Fixtures

    /// What the projector builds from the store's rows, on its own executor.
    private func projection(of container: ModelContainer) async throws -> PortfolioProjection {
        let projector = await PortfolioProjectorClient.makeProjector(modelContainer: container)
        return try await projector.build(PortfolioProjectionRequest(isHistoricalBackfillEnabled: false, now: Self.now))
    }

    private func revaluation(of container: ModelContainer) async throws -> PortfolioRevaluation {
        try await PortfolioValuator.compute(PortfolioValuationRequest(
            projection: projection(of: container),
            prices: PortfolioPriceInputs(livePricesUSD: Self.usdBook, liveChanges24h: [:], usdToDisplayRate: 1, currency: .usd),
            settings: DashboardSettings(dashboard: Self.permissive, isHistoricalBackfillEnabled: false, watchlistIDs: [])))
    }

    /// The production path: the projector's projection of the store, then the tab seam over its
    /// holdings and position metadata.
    private func tab(_ tab: OverviewPositionTab, in container: ModelContainer) async throws -> OverviewPositionTabData {
        let projection = try await projection(of: container)
        return OverviewPositionProjection.tab(
            tab,
            context: .prepared(
                projection.holdings,
                overrides: projection.overrides,
                mappings: projection.mappings,
                settings: Self.permissive,
                usdToDisplayRate: 1,
                prices: ValuationPriceInputs(livePricesUSD: Self.usdBook)),
            positions: projection.positionMeta)
    }

    private func seedAccount(
        in context: ModelContext,
        positionType: PositionType,
        protocolName: String?,
        includeBorrow: Bool) throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let usdc = Asset(
            symbol: "USDC",
            name: "USD Coin",
            coinGeckoId: "usd-coin",
            category: .stablecoin,
            isVerified: true)
        let usdt = Asset(
            symbol: "USDT",
            name: "Tether",
            coinGeckoId: "tether",
            category: .stablecoin,
            isVerified: true)

        var tokens = [PositionToken(role: .supply, amount: 4000, usdValue: 4000, asset: usdc)]
        if includeBorrow {
            tokens.append(PositionToken(role: .borrow, amount: 500, usdValue: 500, asset: usdt))
        }

        let account = Account(
            name: "Primary Wallet",
            kind: .wallet,
            dataSource: .zerion,
            lastSyncedAt: now)
        let position = Position(
            positionType: positionType,
            chain: .ethereum,
            protocolName: protocolName,
            netUSDValue: 3500,
            tokens: tokens,
            account: account,
            syncedAt: now)
        account.positions = [position]

        context.insert(usdc)
        context.insert(usdt)
        context.insert(account)
        try context.save()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Account.self,
            WalletAddress.self,
            Position.self,
            PositionToken.self,
            Asset.self,
            TokenPricingOverride.self,
            TokenIdentityMapping.self,
            HistoricalPricePoint.self,
            CurrencyConversionRatePoint.self,
            PortfolioCategory.self,
            CategorySymbolRule.self,
            PortfolioSnapshot.self,
            AccountSnapshot.self,
            AssetSnapshot.self,
            ProviderPortfolioValuePoint.self,
            ProviderPortfolioHistoryRefresh.self,
            ProviderPnLSnapshot.self,
            ProviderPnLAssetBreakdown.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func render(
        _ view: some View,
        size: CGSize = CGSize(width: 1400, height: 900)) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)

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
        if Self.retainedWindows.count > Self.maxRetainedWindows {
            Self.retainedWindows.removeFirst(Self.retainedWindows.count - Self.maxRetainedWindows)
        }
    }
}
