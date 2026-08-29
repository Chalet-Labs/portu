import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// Guards the contract from issue #103: `OverviewPositionProjection` is the only code
/// that reads position models, and everything it hands to the UI must remain valid
/// after those models are deleted. `SyncEngine` deletes and reinserts positions on the
/// main actor while SwiftUI may still be evaluating a body, and reading a deleted
/// model's property trips a SwiftData assertion that terminates the process.
@MainActor
struct OverviewPositionValueDataTests {
    private static let maxRetainedWindows = 8
    private static var retainedWindows: [NSWindow] = []

    @Test func `projection outlives deletion of its source models`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedAccount(in: context, positionType: .lending, protocolName: "Aave V3", includeBorrow: true)
        let positions = try context.fetch(FetchDescriptor<Position>())

        let groups = OverviewPositionProjection.groups(
            for: .borrowing,
            positions: positions,
            context: projectionContext())

        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.position.title == "Aave V3")
        #expect(group.tokens.map(\.symbol) == ["USDT"])
        #expect(group.value == -500)

        // What the sync does mid-render: delete the positions this data came from.
        for position in positions {
            context.delete(position)
        }
        try context.save()

        // Still readable and renderable, because the projection copied everything.
        #expect(group.position.title == "Aave V3")
        #expect(group.position.chain == .ethereum)
        #expect(group.tokens.map(\.symbol) == ["USDT"])
        #expect(group.value == -500)

        render(OverviewPositionGroupCard(group: group, currencyCode: "USD"))
    }

    @Test func `borrowed tokens subtract from the group total`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedAccount(in: context, positionType: .lending, protocolName: "Aave V3", includeBorrow: true)
        let positions = try context.fetch(FetchDescriptor<Position>())
        let projection = projectionContext()

        let borrowing = try #require(
            OverviewPositionProjection.groups(for: .borrowing, positions: positions, context: projection).first)
        // Only the borrow leg reaches this tab, so the total is negative.
        #expect(borrowing.value == -500)
    }

    @Test func `idle tabs exclude positions that are not idle`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedAccount(in: context, positionType: .lending, protocolName: "Aave V3", includeBorrow: false)
        let positions = try context.fetch(FetchDescriptor<Position>())

        #expect(OverviewPositionProjection.groups(
            for: .idleStables,
            positions: positions,
            context: projectionContext()).isEmpty)
    }

    @Test func `idle stables tab titles wallet positions by account name`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedAccount(in: context, positionType: .idle, protocolName: nil, includeBorrow: false)
        let positions = try context.fetch(FetchDescriptor<Position>())

        let group = try #require(
            OverviewPositionProjection.groups(
                for: .idleStables,
                positions: positions,
                context: projectionContext()).first)

        // No protocol name, so the account name is the fallback title.
        #expect(group.position.title == "Primary Wallet")
        #expect(group.tokens.map(\.symbol) == ["USDC"])
        #expect(group.value == 4000)
    }

    @Test func `placeholder tabs resolve to no groups`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedAccount(in: context, positionType: .idle, protocolName: nil, includeBorrow: true)
        let positions = try context.fetch(FetchDescriptor<Position>())
        let projection = projectionContext()

        for tab in [OverviewPositionTab.futures, .options] {
            #expect(OverviewPositionProjection.groups(
                for: tab,
                positions: positions,
                context: projection).isEmpty)
        }
    }

    @Test func `position tabs render when every position is deleted mid-session`() throws {
        let container = try makeContainer()
        try seedAccount(
            in: container.mainContext,
            positionType: .idle,
            protocolName: nil,
            includeBorrow: true)

        let view = OverviewPositionTabs()
            .modelContainer(container)
            .environment(AppState())
            .frame(width: 1400, height: 900)

        render(view)

        let context = container.mainContext
        for position in try context.fetch(FetchDescriptor<Position>()) {
            context.delete(position)
        }
        try context.save()

        render(view)
    }

    @Test func `mover ordering prefers larger absolute change then symbol`() {
        // Larger magnitude wins regardless of sign.
        #expect(OverviewPriceChangeFeature.isOrderedByChangeMagnitude(
            lhsChange: -50, lhsSymbol: "ZZZ", rhsChange: 10, rhsSymbol: "AAA"))
        #expect(!OverviewPriceChangeFeature.isOrderedByChangeMagnitude(
            lhsChange: 10, lhsSymbol: "AAA", rhsChange: -50, rhsSymbol: "ZZZ"))
        // Equal magnitude falls back to symbol order.
        #expect(OverviewPriceChangeFeature.isOrderedByChangeMagnitude(
            lhsChange: 10, lhsSymbol: "AAA", rhsChange: -10, rhsSymbol: "BBB"))
        #expect(!OverviewPriceChangeFeature.isOrderedByChangeMagnitude(
            lhsChange: -10, lhsSymbol: "BBB", rhsChange: 10, rhsSymbol: "AAA"))
    }

    // MARK: - Fixtures

    /// Permissive visibility so tests exercise projection and grouping, not thresholds.
    private func projectionContext(
        prices: [String: Decimal] = ["usd-coin": 1, "tether": 1],
        changes24h: [String: Decimal] = [:]) -> OverviewPositionContext {
        OverviewPositionContext(
            prices: prices,
            changes24h: changes24h,
            overrideMap: [:],
            mappingMap: [:],
            categoryResolver: .defaults,
            dashboardSettings: TokenDashboardSettings(
                minimumDashboardValue: 0,
                hideUnpriced: false,
                hideDust: false),
            fallbackUSDToDisplayRate: 1)
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
