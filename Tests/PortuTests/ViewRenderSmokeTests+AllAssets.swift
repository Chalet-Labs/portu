import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The All Assets tabs rendered over the in-memory store and read back as text: each list ends with
/// its hidden-balances row (U2), and a list whose every row is hidden shows that row instead of
/// its empty state.
///
/// The seeded store holds ETH (idle, live 3050) and an Aave V3 USDC supply and borrow (live 1);
/// the cases add a $0.50 PEPE position on base under a protocol of its own, so it is hidden on all
/// three tabs.
extension ViewRenderSmokeTests {
    @Test(.renderedTextReadable) func `platforms end with their hidden balances row`() throws {
        let container = try makeContainer()
        try insertDust(into: seededAccount(container), container: container)

        let rows = try tableRows(PlatformsTab(), container: container)
        let names = rows.compactMap(\.first)

        #expect(names.contains("Aave V3"), "\(rows)")
        #expect(names.last == Self.hiddenTitle, "\(rows)")
        #expect(rows.last?.dropFirst().first == AllAssetsFormat.share(0), "\(rows)")
    }

    @Test(.renderedTextReadable) func `platforms show the hidden row when every row is hidden`() throws {
        let container = try makeContainer()
        try seededAccount(container).isActive = false
        try insertDust(into: insertDustAccount(container), container: container)

        let rows = try tableRows(PlatformsTab(), container: container)

        #expect(rows.count == 1, "\(rows)")
        #expect(rows.first?.first == Self.hiddenTitle, "\(rows)")
        #expect(rows.first?.dropFirst().first == AllAssetsFormat.share(1), "\(rows)")
    }

    @Test(.renderedTextReadable) func `networks end with their hidden balances row`() throws {
        let container = try makeContainer()
        try insertDust(into: seededAccount(container), container: container)

        let rows = try tableRows(NetworksTab(), container: container)
        let names = rows.compactMap(\.first)

        #expect(names.contains("Ethereum"), "\(rows)")
        #expect(names == ["Ethereum", Self.hiddenTitle], "\(rows)")
        #expect(rows.last?.dropFirst().first == AllAssetsFormat.share(0), "\(rows)")
    }

    @Test(.renderedTextReadable) func `networks show the hidden row when every row is hidden`() throws {
        let container = try makeContainer()
        try seededAccount(container).isActive = false
        try insertDust(into: insertDustAccount(container), container: container)

        let rows = try tableRows(NetworksTab(), container: container)

        #expect(rows.count == 1, "\(rows)")
        #expect(rows.first?.first == Self.hiddenTitle, "\(rows)")
        #expect(rows.first?.dropFirst().first == AllAssetsFormat.share(1), "\(rows)")
    }

    /// F4: a $20,000 borrow puts the list total below zero, so every share cell reads "—".
    @Test(.renderedTextReadable) func `platforms show no shares when the total is not positive`() throws {
        let container = try makeContainer()
        let usdc = try #require(container.mainContext.fetch(FetchDescriptor<Asset>()).first { $0.symbol == "USDC" })
        let account = try seededAccount(container)
        container.mainContext.insert(Position(
            positionType: .lending,
            chain: .ethereum,
            protocolId: "compound",
            protocolName: "Compound",
            tokens: [PositionToken(role: .borrow, amount: 20000, usdValue: 20000, asset: usdc)],
            account: account,
            syncedAt: Self.syncedAt))
        try container.mainContext.save()

        let rows = try tableRows(PlatformsTab(), container: container)

        #expect(rows.count == 3, "\(rows)")
        #expect(rows.allSatisfy { $0.dropFirst().first == "—" }, "\(rows)")
    }

    /// With Hide unpriced off, an unpriced token shows "—" for its price; the dust row is hidden
    /// after every visible row.
    @Test(.renderedTextReadable) func `assets end with their hidden balances row`() throws {
        let container = try makeContainer()
        let account = try seededAccount(container)
        try insertDust(into: account, container: container)
        let unpriced = Asset(symbol: "NOPE", name: "No Price", category: .other)
        container.mainContext.insert(unpriced)
        container.mainContext.insert(Position(
            positionType: .idle,
            chain: .ethereum,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: 0, asset: unpriced)],
            account: account,
            syncedAt: Self.syncedAt))
        try container.mainContext.save()

        let texts = try assetsTexts(container, hideUnpriced: false)
        let lastAsset = try #require(texts.indices.last { index in
            ["ETH, ", "USDC, ", "NOPE, "].contains { texts[index].hasPrefix($0) }
        }, "\(texts)")
        let nope = texts.first { $0.hasPrefix("NOPE, ") }

        #expect(nope != nil, "\(texts)")
        #expect(texts.indices.last { texts[$0] == Self.hiddenTitle }.map { $0 > lastAsset } == true, "\(texts)")
        #expect(nope?.contains(", —, ") == true, "\(texts)")
    }

    @Test(.renderedTextReadable) func `assets show the hidden row when every row is hidden`() throws {
        let container = try makeContainer()
        try seededAccount(container).isActive = false
        try insertDust(into: insertDustAccount(container), container: container)

        let texts = try assetsTexts(container, hideUnpriced: true)

        #expect(texts.contains(Self.hiddenTitle), "\(texts)")
        #expect(!texts.contains("No assets"), "\(texts)")
    }

    private static let hiddenTitle = ExposureLabels.hiddenRowTitle(rowCount: 1, isAllDust: true)
    private static let syncedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func seededAccount(_ container: ModelContainer) throws -> Account {
        try #require(container.mainContext.fetch(FetchDescriptor<Account>()).first)
    }

    private func insertDustAccount(_ container: ModelContainer) -> Account {
        let account = Account(name: "Dust Wallet", kind: .wallet, dataSource: .zerion)
        container.mainContext.insert(account)
        return account
    }

    private func insertDust(into account: Account, container: ModelContainer) throws {
        let dust = Asset(symbol: "PEPE", name: "Pepe", category: .meme)
        container.mainContext.insert(dust)
        container.mainContext.insert(Position(
            positionType: .farming,
            chain: .base,
            protocolId: "dust-farm",
            protocolName: "Dust Farm",
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: PortfolioValuationFixture.decimal("0.5"), asset: dust)],
            account: account,
            syncedAt: Self.syncedAt))
        try container.mainContext.save()
    }

    /// Renders a tab tall enough to lay out every row, with the dashboard settings on a fresh
    /// defaults suite, and reads it while that suite still exists: `Table` builds its cells lazily.
    private func renderTab<Result>(
        _ view: some View,
        container: ModelContainer,
        hideUnpriced: Bool = true,
        read: (NSView) throws -> Result) throws -> Result {
        let suiteName = "ViewRenderSmokeTests.allAssets.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(hideUnpriced, forKey: TokenDashboardSettings.hideUnpricedKey)
        let store = makeStore(section: .allAssets)
        let appState = AppState()
        appState.bridge(from: store)
        let size = CGSize(width: 1400, height: 1600)
        let hostingView = render(
            view
                .modelContainer(container)
                .environment(appState)
                .defaultAppStorage(defaults)
                .frame(width: size.width, height: size.height),
            size: size)
        return try read(hostingView)
    }

    /// The text of each `Table` row, cell by cell. `Table` keeps its cells out of the accessibility
    /// tree, so they are read from the table view itself.
    private func tableRows(_ view: some View, container: ModelContainer) throws -> [[String]] {
        try renderTab(view, container: container) { hostingView in
            let table = try #require(Self.tableView(in: hostingView))
            return (0 ..< table.numberOfRows).map { row in
                (0 ..< table.numberOfColumns).map { column in
                    table.view(atColumn: column, row: row, makeIfNecessary: true)
                        .map { OverviewModelWiringTests.accessibilityTexts($0).joined(separator: " ") } ?? ""
                }
            }
        }
    }

    private static func tableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView {
            return table
        }
        return view.subviews.lazy.compactMap(tableView(in:)).first
    }

    /// The Assets tab's elements in tree order. A row is a navigation link, so it reads as one
    /// label joining its cells ("ETH, Ethereum, …"); a plain text reads as its value.
    private func assetsTexts(_ container: ModelContainer, hideUnpriced: Bool) throws -> [String] {
        let store = makeStore(section: .allAssets)
        return try renderTab(AssetsTab(store: store), container: container, hideUnpriced: hideUnpriced) {
            Self.accessibilityLabels($0)
        }
    }

    private static func accessibilityLabels(_ element: Any) -> [String] {
        let object = element as AnyObject
        var texts: [String] = []
        if let text = accessibilityString("accessibilityLabel", of: object) ?? accessibilityString("accessibilityValue", of: object) {
            texts.append(text)
        }
        for child in object.accessibilityChildren?() ?? [] {
            texts += accessibilityLabels(child)
        }
        return texts
    }

    private static func accessibilityString(_ selectorName: String, of object: AnyObject) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard
            let object = object as? NSObject,
            object.responds(to: selector),
            let text = object.perform(selector)?.takeUnretainedValue() as? String,
            !text.isEmpty
        else { return nil }
        return text
    }
}
