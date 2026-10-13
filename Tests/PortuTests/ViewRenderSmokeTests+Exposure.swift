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
        let hidden = ExposureLabels.hiddenRowTitle(rowCount: 1, isAllDust: true)
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
        let hidden = ExposureLabels.hiddenRowTitle(rowCount: 1, isAllDust: true)
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
        let hidden = ExposureLabels.hiddenRowTitle(rowCount: 1, isAllDust: true)

        #expect(texts.contains("Exposure by asset"), "\(texts)")
        #expect(texts.filter { $0 == hidden }.count == 2, "\(texts)")
        #expect(!texts.contains("No category exposure"), "\(texts)")
        #expect(!texts.contains("No asset exposure"), "\(texts)")
        #expect(Self.assetPill(texts) == ["Assets", "0"], "\(texts)")
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
