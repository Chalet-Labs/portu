import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// Asset Detail rendered over the in-memory store and read back as text (S7, T4, U4). The seeded
/// store holds ETH (idle on Ethereum, 2 at live 3050, +2.1%) and an Aave V3 USDC supply of 4000 and
/// borrow of 500 (live 1), all in the Primary Wallet.
extension ViewRenderSmokeTests {
    /// T4: an ignored token's row is greyed (an opacity, which the text tree does not carry) with
    /// its Ignored badge in place of a value.
    @Test(.renderedTextReadable) func `asset detail shows an ignored token with its badge and no value`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let scam = Asset(symbol: "SCAM", name: "Scam Token", coinGeckoId: "scam-token", category: .other)
        context.insert(scam)
        context.insert(TokenPricingOverride(assetId: scam.id, isIgnored: true))
        insertPosition(.idle, on: .ethereum, PositionToken(role: .balance, amount: 1000, usdValue: 50, asset: scam), into: account, context: context)
        try context.save()

        let (rows, _) = try readAssetDetail(scam.id, in: container, until: { !$0.isEmpty }, read: Self.tableRows)

        try #require(rows.count == 1, "\(rows)")
        #expect(rows == [["Primary Wallet", "Wallet", "Idle", "Ethereum", AssetDetailFormat.amount(1000), TokenRowLabels.ignored]], "\(rows)")
    }

    /// U4: a counted token with no price shows the Unpriced caption in place of a value.
    @Test(.renderedTextReadable) func `asset detail shows an unpriced token with its caption`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let nope = Asset(symbol: "NOPE", name: "No Price", category: .other)
        context.insert(nope)
        insertPosition(.idle, on: .ethereum, PositionToken(role: .balance, amount: 1, usdValue: 0, asset: nope), into: account, context: context)
        try context.save()

        let (rows, _) = try readAssetDetail(nope.id, in: container, until: { !$0.isEmpty }, read: Self.tableRows)

        try #require(rows.count == 1, "\(rows)")
        #expect(rows == [["Primary Wallet", "Wallet", "Idle", "Ethereum", AssetDetailFormat.amount(1), TokenRowLabels.unpriced]], "\(rows)")
    }

    /// U4, S7: a reward shows its own value, 5 × $1, tagged Not counted (the muting is a colour),
    /// and sorts at its contribution of 0, above the borrow, which is negative.
    @Test(.renderedTextReadable) func `asset detail tags a reward as not counted and signs the borrow`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let usdc = try #require(context.fetch(FetchDescriptor<Asset>()).first { $0.symbol == "USDC" })
        insertPosition(.staking, on: .ethereum, PositionToken(role: .reward, amount: 5, usdValue: 5, asset: usdc), into: account, context: context)
        try context.save()

        let (rows, code) = try readAssetDetail(usdc.id, in: container, until: { $0.count == 3 }, read: Self.tableRows)
        let currency = { (value: Decimal) in AssetDetailFormat.currency(value, code: code) }

        try #require(rows.count == 3, "\(rows)")
        #expect(rows.map(\.last) == [currency(4000), "\(TokenRowLabels.notCounted) \(currency(5))", currency(-500)], "\(rows)")
    }

    /// S7, F4: each chain shows its net amount and net value; a net total that is not positive
    /// (6100 − 9150) shows every share as "—". The header shows the V5 price and its fraction.
    @Test(.renderedTextReadable) func `asset detail lists each chain's net with a dash share`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let eth = try #require(context.fetch(FetchDescriptor<Asset>()).first { $0.symbol == "ETH" })
        insertPosition(.lending, on: .arbitrum, PositionToken(role: .borrow, amount: 3, usdValue: 9000, asset: eth), into: account, context: context)
        try context.save()

        let (texts, code) = try readAssetDetail(eth.id, in: container, until: { $0.contains("On Networks") }, read: Self.accessibilityLabels)
        let currency = { (value: Decimal) in AssetDetailFormat.currency(value, code: code) }
        let networks = Array(texts.drop { $0 != "On Networks" }.dropFirst().prefix(8))

        try #require(texts.contains("On Networks"), "\(texts)")
        #expect(texts.contains(currency(3050)), "\(texts)")
        #expect(texts.contains(AssetDetailFormat.change(Decimal(string: "0.021") ?? 0)), "\(texts)")
        #expect(texts.contains(AssetDetailFormat.amount(-1)), "\(texts)")
        #expect(texts.contains(currency(-3050)), "\(texts)")
        #expect(networks == [
            "Ethereum", AssetDetailFormat.amount(2), "—", currency(6100),
            "Arbitrum", AssetDetailFormat.amount(-3), "—", currency(-9150)
        ], "\(texts)")
    }

    private func insertPosition(
        _ type: PositionType,
        on chain: Chain,
        _ token: PositionToken,
        into account: Account,
        context: ModelContext) {
        context.insert(Position(
            positionType: type,
            chain: chain,
            tokens: [token],
            account: account,
            syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }

    /// The text of each `Table` row, cell by cell. `Table` keeps its cells out of the accessibility
    /// tree, so they are read from the table view itself.
    private static func tableRows(_ view: NSView) -> [[String]] {
        guard let table = tableView(in: view) else { return [] }
        return (0 ..< table.numberOfRows).map { row in
            (0 ..< table.numberOfColumns).map { column in
                table.view(atColumn: column, row: row, makeIfNecessary: true)
                    .map { OverviewModelWiringTests.accessibilityTexts($0).joined(separator: " ") } ?? ""
            }
        }
    }

    /// Renders the page tall enough for every section, with the dashboard settings on a fresh
    /// defaults suite, and reads it while that suite still exists, spinning the run loop until
    /// `isReady` or two seconds pass. Returns what was read and the currency code it is shown in.
    private func readAssetDetail<Result>(
        _ assetId: UUID,
        in container: ModelContainer,
        until isReady: (Result) -> Bool,
        read: (NSView) throws -> Result) throws -> (result: Result, currencyCode: String) {
        let suiteName = "ViewRenderSmokeTests.assetDetail.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(section: .allAssets)
        let appState = AppState()
        appState.bridge(from: store)
        let size = CGSize(width: 1400, height: 1800)
        let hostingView = render(
            AssetDetailView(assetId: assetId, store: store)
                .modelContainer(container)
                .environment(appState)
                .defaultAppStorage(defaults)
                .frame(width: size.width, height: size.height),
            size: size)

        var result = try read(hostingView)
        let deadline = Date().addingTimeInterval(2)
        while !isReady(result), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            result = try read(hostingView)
        }
        return (result, appState.currencyCode)
    }
}
