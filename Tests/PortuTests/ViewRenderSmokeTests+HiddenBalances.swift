import AppKit
import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

extension ViewRenderSmokeTests {
    @Test(arguments: [OverviewPositionTab.idleStables, .borrowing])
    func `position cards render their hidden balances line`(_ tab: OverviewPositionTab) {
        let data = OverviewPositionProjection.tab(
            tab,
            context: OverviewValuationFixture.context(),
            positions: OverviewValuationFixture.positions)
        #expect(data.groups.contains { $0.hidden != nil })

        let view = VStack {
            ForEach(data.groups) { group in
                OverviewPositionGroupCard(group: group, currencyCode: "USD")
            }
            OverviewHiddenBalancesLine(text: "+ $ 0.4 in 1 small balance")
                .overviewPositionPanel()
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 900, height: 400)

        render(view, size: CGSize(width: 900, height: 400))
    }

    /// A dust holding and a dust borrow in a position of its own, so the donut, Health and the
    /// tabs have hidden rows to render.
    @Test func `overview renders a portfolio with hidden balances`() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        let dust = Asset(symbol: "DUST", name: "Dust Coin", category: .other)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        context.insert(dust)
        context.insert(Position(
            positionType: .idle,
            chain: .base,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: OverviewValuationFixture.decimal("0.5"), asset: dust)],
            account: account,
            syncedAt: now))
        context.insert(Position(
            positionType: .lending,
            chain: .base,
            protocolName: "Dust Lend",
            tokens: [PositionToken(role: .borrow, amount: 1, usdValue: OverviewValuationFixture.decimal("0.4"), asset: dust)],
            account: account,
            syncedAt: now))
        try context.save()

        let store = makeStore(section: .overview)
        let appState = AppState()
        appState.bridge(from: store)
        let view = ContentView(store: store)
            .modelContainer(container)
            .environment(appState)
            .frame(width: 1400, height: 900)

        render(view)
    }
}
