import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// All Positions rendered over the in-memory store and read back as text (S6, T4, U4). The seeded
/// store holds ETH (idle, live 3050) and an Aave V3 USDC supply and $500 borrow (live 1). Each
/// token added here sits alone in a section of its own, so its row ends at the next section title.
extension ViewRenderSmokeTests {
    /// T4 and U4: an ignored token is greyed with its Ignored badge and no value; a reward shows its
    /// own value, 5 × $1, tagged Not counted (the muting is a colour, which the text tree does not
    /// carry); a counted token with no price shows the Unpriced caption and no value; a borrow row
    /// is negative.
    @Test(.renderedTextReadable) func `all positions token rows show their state`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let scam = Asset(symbol: "SCAM", name: "Scam Token", coinGeckoId: "scam-token", category: .other)
        let reward = Asset(symbol: "RWD", name: "Reward Coin", coinGeckoId: "usd-coin", category: .other)
        let unpriced = Asset(symbol: "NOPE", name: "No Price", category: .other)
        context.insert(scam)
        context.insert(reward)
        context.insert(unpriced)
        context.insert(TokenPricingOverride(assetId: scam.id, isIgnored: true))
        insertPosition(.vesting, PositionToken(role: .balance, amount: 1000, usdValue: 50, asset: scam), into: account, context: context)
        insertPosition(.staking, PositionToken(role: .reward, amount: 5, usdValue: 5, asset: reward), into: account, context: context)
        insertPosition(.farming, PositionToken(role: .balance, amount: 1, usdValue: 0, asset: unpriced), into: account, context: context)
        try context.save()

        let (texts, code) = try allPositionsTexts(container) { $0.contains("SCAM") && $0.contains("NOPE") }
        let currency = { (value: Decimal) in AllPositionsFormat.currency(value, code: code) }
        let amount = AllPositionsFormat.amount
        let borrow = texts.indices.first { texts[$0] == TokenRole.borrow.displayLabel && texts.dropFirst($0 + 1).first == "USDC" }

        try #require(texts.contains("SCAM"), "\(texts)")
        try #require(texts.contains("RWD"), "\(texts)")
        try #require(texts.contains("NOPE"), "\(texts)")
        let borrowIndex = try #require(borrow, "\(texts)")
        withKnownIssue("All Positions rows still show the display-book value, unsigned, with no state") {
            #expect(Self.rowTexts(texts, after: "SCAM") == [TokenRowLabels.ignored, amount(1000)], "\(texts)")
            #expect(Self.rowTexts(texts, after: "RWD") == [TokenRowLabels.notCounted, amount(5), currency(5)], "\(texts)")
            #expect(Self.rowTexts(texts, after: "NOPE") == [amount(1), TokenRowLabels.unpriced], "\(texts)")
            #expect(Array(texts.dropFirst(borrowIndex + 2).prefix(2)) == [amount(500), currency(-500)], "\(texts)")
        }
    }

    /// The texts after a row's symbol, up to the next row's role label, section title or the
    /// sidebar.
    private static func rowTexts(_ texts: [String], after symbol: String) -> [String] {
        let stops = Set(TokenRole.allCases.map(\.displayLabel) + PositionType.allCases.map(AllPositionsFeature.sectionTitle) + ["Filter"])
        return Array(texts.drop { $0 != symbol }.dropFirst().prefix { !stops.contains($0) })
    }

    private func insertPosition(_ type: PositionType, _ token: PositionToken, into account: Account, context: ModelContext) {
        context.insert(Position(
            positionType: type,
            chain: .ethereum,
            tokens: [token],
            account: account,
            syncedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }

    /// Renders the page tall enough for every card, with the dashboard settings on a fresh defaults
    /// suite, and reads the text while that suite still exists, spinning the run loop until
    /// `isReady` or two seconds pass. Returns the texts and the currency code they are shown in.
    private func allPositionsTexts(
        _ container: ModelContainer,
        isReady: ([String]) -> Bool) throws -> (texts: [String], currencyCode: String) {
        let suiteName = "ViewRenderSmokeTests.allPositions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState()
        appState.bridge(from: makeStore(section: .allPositions))
        let size = CGSize(width: 1400, height: 2400)
        let hostingView = render(
            AllPositionsView()
                .modelContainer(container)
                .environment(appState)
                .defaultAppStorage(defaults)
                .frame(width: size.width, height: size.height),
            size: size)

        var texts = Self.accessibilityLabels(hostingView)
        let deadline = Date().addingTimeInterval(2)
        while !isReady(texts), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            texts = Self.accessibilityLabels(hostingView)
        }
        return (texts, appState.currencyCode)
    }
}
