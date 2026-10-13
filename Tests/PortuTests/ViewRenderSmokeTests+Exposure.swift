import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The Exposure page rendered over the in-memory store and read back through the accessibility
/// tree: each table ends with its hidden-balances row (U2), and a table whose every row is hidden
/// shows that row instead of its empty state.
extension ViewRenderSmokeTests {
    /// A $0.50 PEPE holding sits in a category of its own, so both tables hide one dust row after
    /// their ETH and USDC rows.
    @Test(.renderedTextReadable) func `exposure tables end with their hidden balances row`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        insertDust(into: account, context: context)
        try context.save()

        let texts = try exposureTexts(container)
        let hidden = HiddenBalancesLabel.title(rowCount: 1, isAllDust: true)
        let categoryTable = try #require(texts.firstIndex(of: "Exposure by asset category"), "\(texts)")
        let assetTable = try #require(texts.firstIndex(of: "Exposure by asset"), "\(texts)")
        let lastCategoryRow = try #require(texts.indices.last { $0 < assetTable && ["ETH", "Stablecoins"].contains(texts[$0]) }, "\(texts)")
        let lastAssetRow = try #require(texts.indices.last { $0 > assetTable && ["ETH", "USDC"].contains(texts[$0]) }, "\(texts)")
        let hiddenRows = texts.indices.filter { texts[$0] == hidden }

        #expect(categoryTable < lastCategoryRow)
        #expect(hiddenRows.count == 2, "\(texts)")
        #expect(hiddenRows.first.map { $0 > lastCategoryRow && $0 < assetTable } == true, "\(texts)")
        #expect(hiddenRows.last.map { $0 > lastAssetRow } == true, "\(texts)")
        // The pill counts ETH and USDC, not the hidden line.
        #expect(Self.assetPill(texts) == ["Assets", "2"], "\(texts)")
    }

    /// Decided 2026-10-13: the hidden line's spot, liabilities and Spot Net cells show cents, so
    /// the $0.50 PEPE line reads "$ 0.50", not "$ 0". An ordinary row keeps whole units.
    @Test(.renderedTextReadable) func `exposure hidden line shows its amounts with cents`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        insertDust(into: account, context: context)
        try context.save()

        let texts = try exposureTexts(container)
        let hidden = HiddenBalancesLabel.title(rowCount: 1, isAllDust: true)
        let assetTable = try #require(texts.firstIndex(of: "Exposure by asset"), "\(texts)")
        let hiddenRow = try #require(texts.indices.last { $0 > assetTable && texts[$0] == hidden }, "\(texts)")
        let ethRow = try #require(texts.indices.first { $0 > assetTable && texts[$0] == "ETH" }, "\(texts)")
        let cents = { (value: Decimal) in ExposureFormat.currency(value, fractionDigits: 2) }
        let whole = { (value: Decimal) in ExposureFormat.currency(value, fractionDigits: 0) }
        let half = PortfolioValuationFixture.decimal("0.5")

        // Spot / liabilities, then Spot Net.
        #expect(Array(texts.dropFirst(hiddenRow + 1).prefix(4)) == [cents(half), "/", cents(0), cents(half)], "\(texts)")
        // ETH: 2 × $3,050 live.
        #expect(Array(texts.dropFirst(ethRow + 1).prefix(4)) == [whole(6100), "/", whole(0), whole(6100)], "\(texts)")
    }

    /// S4's 2×2 summary over the seeded store: Spot is ETH 2 × $3,050 + USDC $4,000, Liabilities the
    /// $500 USDC borrow, shown positive (A2), and Net exposure leaves out the stablecoin. The USDC row
    /// shows its borrow unsigned too.
    @Test(.renderedTextReadable) func `exposure summary cards and a borrow read unsigned`() throws {
        let texts = try exposureTexts(makeContainer())
        let cents = { (value: Decimal) in ExposureFormat.currency(value, fractionDigits: 2) }
        let whole = { (value: Decimal) in ExposureFormat.currency(value, fractionDigits: 0) }
        let assetTable = try #require(texts.firstIndex(of: "Exposure by asset"), "\(texts)")
        let usdcRow = try #require(texts.indices.first { $0 > assetTable && texts[$0] == "USDC" }, "\(texts)")

        #expect(Self.card("Spot total", texts) == [cents(10100)], "\(texts)")
        #expect(Self.card("Liabilities", texts) == [cents(500)], "\(texts)")
        #expect(Self.card("Net total", texts) == [cents(9600)], "\(texts)")
        let share = ExposureFormat.percent(Decimal(6100) / Decimal(10100), fractionDigits: 2)
        #expect(Self.card(Self.netExposureTitle, texts, count: 2) == [cents(6100), "\(share) of spot total"], "\(texts)")
        // Spot / liabilities, then Spot Net.
        #expect(Array(texts.dropFirst(usdcRow + 1).prefix(4)) == [whole(4000), "/", whole(500), whole(3500)], "\(texts)")
    }

    /// Decided 2026-10-13: with no spot at all, "% of spot" reads "—", on the row and on the Net
    /// exposure card. The only active holding is a $100 USDC borrow.
    @Test(.renderedTextReadable) func `exposure shows no ratio when spot is not positive`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let seeded = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let usdc = try #require(context.fetch(FetchDescriptor<Asset>()).first { $0.symbol == "USDC" })
        seeded.isActive = false
        let account = Account(name: "Borrow Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(account)
        context.insert(Position(
            positionType: .lending,
            chain: .ethereum,
            protocolId: "aave-v3",
            protocolName: "Aave V3",
            tokens: [PositionToken(role: .borrow, amount: 100, usdValue: 100, asset: usdc)],
            account: account,
            syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        try context.save()

        let texts = try exposureTexts(container)
        let cents = { (value: Decimal) in ExposureFormat.currency(value, fractionDigits: 2) }
        let whole = { (value: Decimal) in ExposureFormat.currency(value, fractionDigits: 0) }
        let assetTable = try #require(texts.firstIndex(of: "Exposure by asset"), "\(texts)")
        let usdcRow = try #require(texts.indices.first { $0 > assetTable && texts[$0] == "USDC" }, "\(texts)")

        // Spot / liabilities, Spot Net, Net Exposure, then "% of spot".
        #expect(Array(texts.dropFirst(usdcRow + 1).prefix(6)) == [whole(0), "/", whole(100), whole(-100), cents(-100), "—"], "\(texts)")
        #expect(Self.card(Self.netExposureTitle, texts, count: 2) == [cents(0), "— of spot total"], "\(texts)")
    }

    /// Every active holding is dust: neither table has a visible row, and each shows its hidden
    /// line, not "No … exposure".
    @Test(.renderedTextReadable) func `exposure shows the hidden row when every row is hidden`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let seeded = try #require(context.fetch(FetchDescriptor<Account>()).first)
        seeded.isActive = false
        let account = Account(name: "Dust Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(account)
        insertDust(into: account, context: context)
        try context.save()

        let texts = try exposureTexts(container)
        let hidden = HiddenBalancesLabel.title(rowCount: 1, isAllDust: true)

        #expect(texts.contains("Exposure by asset"), "\(texts)")
        #expect(texts.filter { $0 == hidden }.count == 2, "\(texts)")
        #expect(!texts.contains("No category exposure"), "\(texts)")
        #expect(!texts.contains("No asset exposure"), "\(texts)")
        #expect(Self.assetPill(texts) == ["Assets", "0"], "\(texts)")
    }

    private static let netExposureTitle = "Net exposure (excl. stablecoins)"

    /// The texts a summary card shows after its title.
    private static func card(_ title: String, _ texts: [String], count: Int = 1) -> [String] {
        Array(texts.drop { $0 != title }.dropFirst().prefix(count))
    }

    /// The Assets pill's title and count, in tree order.
    private static func assetPill(_ texts: [String]) -> [String] {
        Array(texts.drop { $0 != ExposureLabels.assetCountPillTitle }.prefix(2))
    }

    private func insertDust(into account: Account, context: ModelContext) {
        let dust = Asset(symbol: "PEPE", name: "Pepe", category: .meme)
        context.insert(dust)
        context.insert(Position(
            positionType: .idle,
            chain: .base,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: PortfolioValuationFixture.decimal("0.5"), asset: dust)],
            account: account,
            syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }

    /// Renders `ExposureView` tall enough that both tables lay out every row, with the dashboard
    /// settings at their defaults on a fresh defaults suite, and returns its texts in tree order.
    private func exposureTexts(_ container: ModelContainer) throws -> [String] {
        let suiteName = "ViewRenderSmokeTests.exposure.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(section: .exposure)
        let appState = AppState()
        appState.bridge(from: store)
        let size = CGSize(width: 1400, height: 2400)
        let hostingView = render(
            ExposureView(store: store)
                .modelContainer(container)
                .environment(appState)
                .defaultAppStorage(defaults)
                .frame(width: size.width, height: size.height),
            size: size)
        return OverviewModelWiringTests.accessibilityTexts(hostingView)
    }
}
