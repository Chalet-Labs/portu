import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The Tokens tab rendered over an in-memory store and read back as text (S8, T4, U4). The seeded
/// store holds ETH (idle, live 3050) and an Aave V3 USDC supply and borrow (live 1).
extension ViewRenderSmokeTests {
    /// AGENT-DECIDED 10 (CRITIC C9): the Settings window is its own scene, so it sees closes only when
    /// `SettingsView` mounts the historical provider. CLS has no live price and no sync value, so a
    /// today's close is its only possible source. The real root is hosted, on the Tokens tab.
    @Test(.renderedTextReadable) func `the settings window values a token from its close`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let today = HistoricalPriceCalendar.utcStartOfDay(for: .now)
        let asset = Asset(symbol: "CLS", name: "Close Coin", coinGeckoId: "close-coin", category: .other)
        let account = Account(name: "Close Wallet", kind: .wallet, dataSource: .zerion)
        container.mainContext.insert(asset)
        container.mainContext.insert(account)
        container.mainContext.insert(Position(
            positionType: .idle,
            chain: .ethereum,
            tokens: [PositionToken(role: .balance, amount: 2, usdValue: 0, asset: asset)],
            account: account,
            syncedAt: today.addingTimeInterval(-86400)))
        container.mainContext.insert(HistoricalPricePoint(coinGeckoId: "close-coin", day: today, currency: .usd, price: 20))
        try container.mainContext.save()
        let store = makeStore(section: .overview)
        let settings = SettingsView(store: store, secretStore: InMemorySecretStore(), initialTab: .tokens)
        let value = TokenSettingsFormat.currency(40, currency: .default)

        let texts = try tokenSettingsTexts(settings, container: container, backfillEnabled: true) {
            $0.contains(value)
        }

        #expect(texts.contains("CLS"), "\(texts)")
        #expect(texts.contains(value), "\(texts)")
        #expect(Array(texts.drop { $0 != "CLS" }).contains(TokenPricingSource.close.rawValue), "\(texts)")
    }

    /// S8 and T4: an ignored asset stays listed, greyed, with its Ignored badge, "—" as its source and
    /// no value. ETH sorts last, as it has no value.
    @Test(.renderedTextReadable) func `an ignored token settings row is listed with no value`() throws {
        let container = try makeContainer()
        let eth = try #require(container.mainContext.fetch(FetchDescriptor<Asset>()).first { $0.symbol == "ETH" })
        container.mainContext.insert(TokenPricingOverride(assetId: eth.id, isIgnored: true))
        try container.mainContext.save()

        let texts = try tokenSettingsTexts(TokenSettingsView(), container: container) { $0.contains("ETH") }
        let ethRow = Self.rowTexts(texts, symbol: "ETH")

        #expect(ethRow.first == "ETH", "\(texts)")
        #expect(ethRow.contains(TokenSettingsLabels.ignored), "\(texts)")
        #expect(ethRow.contains("—"), "\(texts)")
        #expect(!ethRow.contains { $0.hasPrefix(Self.currencyPrefix) }, "\(ethRow)")
    }

    /// U4: a reward-only asset carries the Not counted badge, and the counts bar a Not counted chip.
    /// Its value line shows the reward's own value, 5 × $1 (S8 as amended); the muting is a colour,
    /// which the text tree does not carry.
    @Test(.renderedTextReadable) func `a reward-only token settings row is marked not counted`() throws {
        let container = try makeContainer()
        let account = try #require(container.mainContext.fetch(FetchDescriptor<Account>()).first)
        let reward = Asset(symbol: "RWD", name: "Reward Coin", coinGeckoId: "usd-coin", category: .other)
        container.mainContext.insert(reward)
        container.mainContext.insert(Position(
            positionType: .staking,
            chain: .ethereum,
            protocolId: "lido",
            protocolName: "Lido",
            tokens: [PositionToken(role: .reward, amount: 5, usdValue: 5, asset: reward)],
            account: account,
            syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        try container.mainContext.save()

        let texts = try tokenSettingsTexts(TokenSettingsView(), container: container) { $0.contains("RWD") }
        let rewardRow = Self.rowTexts(texts, symbol: "RWD")

        #expect(rewardRow.first == "RWD", "\(texts)")
        #expect(rewardRow.contains(TokenSettingsLabels.notCounted), "\(texts)")
        #expect(rewardRow.contains(TokenSettingsFormat.currency(5, currency: .default)), "\(rewardRow)")
        #expect(texts.count { $0 == TokenSettingsLabels.notCounted } == 2, "\(texts)")
    }

    /// U4: a counted, unpriced row shows its Unpriced caption and no value. NOPE has no price ID and
    /// no sync value, so it sorts last, after ETH and USDC.
    @Test(.renderedTextReadable) func `an unpriced token settings row shows no value`() throws {
        let container = try makeContainer()
        let account = try #require(container.mainContext.fetch(FetchDescriptor<Account>()).first)
        let unpriced = Asset(symbol: "NOPE", name: "No Price", category: .other)
        container.mainContext.insert(unpriced)
        container.mainContext.insert(Position(
            positionType: .idle,
            chain: .ethereum,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: 0, asset: unpriced)],
            account: account,
            syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        try container.mainContext.save()

        let texts = try tokenSettingsTexts(TokenSettingsView(), container: container) { $0.contains("NOPE") }
        let unpricedRow = Self.rowTexts(texts, symbol: "NOPE")

        #expect(unpricedRow.first == "NOPE", "\(texts)")
        #expect(unpricedRow.contains(TokenPricingSource.unpriced.rawValue), "\(texts)")
        #expect(!unpricedRow.contains { $0.hasPrefix(Self.currencyPrefix) }, "\(unpricedRow)")
    }

    /// S8: the tab lists the active accounts only. OFF is held by an archived account alone, and its
    /// sync value would price it, so it would show up on any all-accounts input.
    @Test(.renderedTextReadable) func `token settings leaves out tokens held only by inactive accounts`() throws {
        let container = try makeContainer()
        let archived = Account(name: "Archived Wallet", kind: .wallet, dataSource: .zerion, isActive: false)
        let offline = Asset(symbol: "OFF", name: "Archived Coin", category: .other)
        container.mainContext.insert(archived)
        container.mainContext.insert(offline)
        container.mainContext.insert(Position(
            positionType: .idle,
            chain: .ethereum,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: 50, asset: offline)],
            account: archived,
            syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        try container.mainContext.save()

        let texts = try tokenSettingsTexts(TokenSettingsView(), container: container) {
            $0.contains("ETH") && $0.contains("USDC")
        }

        #expect(texts.contains("ETH"), "\(texts)")
        #expect(texts.contains("USDC"), "\(texts)")
        #expect(!texts.contains("OFF"), "\(texts)")
        #expect(!texts.contains("Archived Coin"), "\(texts)")
    }

    /// The value line is the only text the row formats with the currency symbol; the amount has none.
    private static let currencyPrefix = "\(FiatCurrency.default.symbol) "

    /// One row's texts: from its symbol up to the next seeded row's symbol.
    private static func rowTexts(_ texts: [String], symbol: String) -> [String] {
        let rowSymbols: Set = ["ETH", "USDC", "NOPE", "RWD", "CLS"]
        let row = texts.drop { $0 != symbol }
        return [String](row.prefix(1)) + row.dropFirst().prefix { !rowSymbols.contains($0) }
    }

    /// Renders tall enough for every row, with the settings on a fresh defaults suite, and reads the
    /// text while that suite still exists, spinning the run loop until `isReady` or two seconds pass.
    private func tokenSettingsTexts(
        _ view: some View,
        container: ModelContainer,
        backfillEnabled: Bool = false,
        isReady: ([String]) -> Bool) throws -> [String] {
        let suiteName = "ViewRenderSmokeTests.tokenSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(backfillEnabled, forKey: HistoricalPriceBackfillSettings.isEnabledKey)
        let appState = AppState()
        appState.bridge(from: makeStore(section: .overview))
        let size = CGSize(width: 1400, height: 2400)
        let hostingView = render(
            view
                .modelContainer(container)
                .environment(appState)
                .defaultAppStorage(defaults)
                .environment(\.colorScheme, .dark)
                .frame(width: size.width, height: size.height),
            size: size)

        var texts = Self.accessibilityLabels(hostingView)
        let deadline = Date().addingTimeInterval(2)
        while !isReady(texts), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            texts = Self.accessibilityLabels(hostingView)
        }
        return texts
    }
}
