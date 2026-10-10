import Foundation
import PortuCore
import Testing

struct ValuationFilterTests {
    private typealias Fixture = ValuationFixtures

    @Test func `dust token and dust borrow are hidden but still counted in the totals`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("DUST", Fixture.decimal("0.8"))),
            Fixture.input(Fixture.synced("LOAN", Fixture.decimal("0.5"), role: .borrow))
        ])

        let list = byAsset(valuation, .net)

        #expect(list.visibleRows.isEmpty)
        #expect(list.rows.map(\.status) == [.dust, .dust])
        #expect(list.hidden.rowCount == 2)
        #expect(list.totals.net == Fixture.decimal("0.3"))
        #expect(valuation.totals.net == Fixture.decimal("0.3"))
    }

    @Test func `dust threshold is usd and is never scaled by the display rate`() throws {
        let small = Fixture.synced("SMALL", Fixture.decimal("0.8"))
        let large = Fixture.synced("LARGE", Fixture.decimal("1.5"))
        let valuation = Fixture.valuation([Fixture.input(small), Fixture.input(large)])

        let list = byAsset(valuation, .net)
        let rate = Fixture.decimal("0.5")

        let row = try #require(list.visibleRows.first)
        #expect(list.visibleRows.map(\.key) == [large.assetId])
        #expect(row.displayValue(rate: rate) == Fixture.decimal("0.75"))
        #expect(list.hidden.display(rate: rate).net == Fixture.decimal("0.4"))
    }

    @Test func `row mixing an ignored supply with another asset's reward is ignored and not hidden`() {
        let supply = Fixture.token("IGN", coinGeckoId: "ign", role: .supply, amount: 1, usdValue: Fixture.decimal("0.1"))
        let reward = Fixture.token("REW", coinGeckoId: "rew", role: .reward, amount: 1, usdValue: 5)
        let valuation = Fixture.valuation(
            [Fixture.input(supply), Fixture.input(reward)],
            overrides: [Fixture.ignore(supply)])

        let list = Fixture.list(valuation, .net) { _ in "category" }

        #expect(list.rows.map(\.status) == [.ignored])
        #expect(list.dashboardRows.isEmpty)
        #expect(list.hidden.isEmpty)
        #expect(list.totals.net == 0)
    }

    @Test func `reward only asset is not counted and has no dashboard row`() {
        let reward = Fixture.token("REW", coinGeckoId: "rew", role: .reward, amount: 1, usdValue: 500)
        let valuation = Fixture.valuation([Fixture.input(reward)])

        let list = byAsset(valuation, .net)

        #expect(list.rows.map(\.status) == [.notCounted])
        #expect(list.dashboardRows.isEmpty)
        #expect(list.visibleRows.isEmpty)
        #expect(list.hidden.isEmpty)
    }

    @Test func `borrow only asset keeps its exposure row and its liabilities count`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 1000, role: .supply)),
            Fixture.input(Fixture.synced("USDC", 400, role: .borrow))
        ])

        let exposure = byAsset(valuation, .net)

        #expect(exposure.visibleRows.count == 2)
        #expect(exposure.visibleRows.reduce(0) { $0 + $1.totals.debt } == valuation.totals.debt)
        #expect(exposure.visibleRows.reduce(0) { $0 + $1.totals.gross } == valuation.totals.gross)
    }

    @Test func `exposure ratio divides a row's net by the list's spot total`() throws {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 300, assetId: assetId, role: .supply)),
            Fixture.input(Fixture.synced("ETH", 100, assetId: assetId, role: .borrow)),
            Fixture.input(Fixture.synced("BTC", 100))
        ])
        let exposure = byAsset(valuation, .net)
        let eth = try #require(exposure.rows.first)

        #expect(exposure.ratio(of: eth, to: .gross) == Fixture.decimal("0.5"))
        #expect(exposure.ratio(of: eth, to: .net) == exposure.weight(of: eth))
        #expect(byAsset(Fixture.valuation([]), .net).ratio(of: eth, to: .gross) == nil)
    }

    @Test func `small supply against a large borrow is visible on exposure`() throws {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", Fixture.decimal("0.8"), assetId: assetId, role: .supply)),
            Fixture.input(Fixture.synced("ETH", 1000, assetId: assetId, role: .borrow))
        ])

        let row = try #require(byAsset(valuation, .net).rows.first)

        #expect(row.status == .priced)
        #expect(row.isVisible)
        #expect(row.filterValue == 1000)
    }

    @Test func `a dollar of debt beside 99 cents of gross is dust on the donut and visible on exposure`() throws {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", Fixture.decimal("0.99"), assetId: assetId, role: .supply)),
            Fixture.input(Fixture.synced("ETH", Fixture.decimal("1.01"), assetId: assetId, role: .borrow))
        ])

        let donut = byAsset(valuation, .gross)
        let exposure = byAsset(valuation, .net)

        let donutRow = try #require(donut.rows.first)
        let exposureRow = try #require(exposure.rows.first)
        #expect(donutRow.status == .dust)
        #expect(donutRow.totals.debt == 0)
        #expect(exposureRow.status == .priced)
        #expect(exposureRow.isVisible)
    }

    @Test func `dust asset hides on the asset table while its category row stays visible`() throws {
        let category = Fixture.eth
        let dust = Fixture.synced("DUST", Fixture.decimal("0.5"), portfolioCategory: category)
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 100, portfolioCategory: category)),
            Fixture.input(dust),
            Fixture.input(Fixture.synced("LOAN", Fixture.decimal("0.3"), role: .borrow, portfolioCategory: category)),
            Fixture.input(Fixture.synced("USDC", 50, portfolioCategory: Fixture.stablecoins))
        ])

        let assets = byAsset(valuation, .net)
        let categories = Fixture.list(valuation, .net) { $0.token.portfolioCategory.id }

        let dustRow = try #require(assets.rows.first { $0.key == dust.assetId })
        let categoryRow = try #require(categories.rows.first { $0.key == category.id })
        #expect(!dustRow.isVisible)
        #expect(categoryRow.isVisible)
        for list in [assets.ranked(), categories.ranked()] {
            let visible = list.rows.reduce(ValuationTotals.zero) { $0 + $1.totals }
            #expect(visible.gross + list.hidden.gross == valuation.totals.gross)
            #expect(visible.debt + list.hidden.debt == valuation.totals.debt)
            #expect(visible.net + list.hidden.net == valuation.totals.net)
        }
    }

    @Test func `health groups the same symbol held as two assets into one row`() throws {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 100)),
            Fixture.input(Fixture.synced("ETH", 50)),
            Fixture.input(Fixture.synced("BTC", 30))
        ])

        let health = bySymbol(valuation)

        #expect(health.rows.map(\.key) == ["ETH|ETH", "BTC|BTC"])
        #expect(try #require(health.rows.first).value == 150)
    }

    @Test func `health without a positive net group has no rows and no shares`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 100, role: .borrow))
        ])

        let health = bySymbol(valuation)

        #expect(health.rows.isEmpty)
        #expect(health.ranked().shares == nil)
    }

    @Test func `net negative asset has no health row and health sums its positive nets`() throws {
        let ethId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 100, assetId: ethId, role: .supply)),
            Fixture.input(Fixture.synced("ETH", 300, assetId: ethId, role: .borrow)),
            Fixture.input(Fixture.synced("BTC", 60)),
            Fixture.input(Fixture.synced("DUST", Fixture.decimal("0.5")))
        ])

        let health = bySymbol(valuation)
        let ranked = health.ranked()

        #expect(health.rows.map(\.key) == ["BTC|BTC", "DUST|DUST"])
        #expect(ranked.rows.reduce(0) { $0 + $1.value } + ranked.hidden.net == Fixture.decimal("60.5"))
        #expect(health.total == Fixture.decimal("60.5"))
        let btc = try #require(health.rows.first)
        #expect(health.weight(of: btc) == 60 / Fixture.decimal("60.5"))
    }

    @Test func `health drops zero net groups instead of hiding them`() {
        let hedged = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 100)),
            Fixture.input(Fixture.token("UNP", coinGeckoId: "unp", amount: 10, usdValue: 0)),
            Fixture.input(Fixture.synced("USDC", 40, assetId: hedged, role: .supply)),
            Fixture.input(Fixture.synced("USDC", 40, assetId: hedged, role: .borrow))
        ])

        let health = bySymbol(valuation)

        #expect(health.rows.map(\.key) == ["ETH|ETH"])
        #expect(health.hidden.isEmpty)
        #expect(health.total == 100)
    }

    @Test func `hedged protocol is not dust on platforms`() throws {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 50000, role: .supply), positionType: .lending, protocolId: "aave"),
            Fixture.input(
                Fixture.synced("USDC", Fixture.decimal("49999.2"), role: .borrow),
                positionType: .lending,
                protocolId: "aave")
        ])

        let platforms = Fixture.list(valuation, .net) { $0.position.protocolId }

        let row = try #require(platforms.rows.first)
        #expect(row.value == Fixture.decimal("0.8"))
        #expect(row.status == .priced)
        #expect(row.isVisible)
    }

    @Test func `borrow only asset has no donut row and is not in the donut hidden summary`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 100)),
            Fixture.input(Fixture.synced("LOAN", Fixture.decimal("0.5"), role: .borrow))
        ])

        let donut = byAsset(valuation, .gross)

        #expect(donut.rows.count == 1)
        #expect(donut.hidden.isEmpty)
        #expect(donut.total == valuation.totals.gross)
    }

    @Test func `borrowing tab is built from borrow tokens only`() throws {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 100, assetId: assetId, role: .supply)),
            Fixture.input(Fixture.synced("ETH", 40, assetId: assetId, role: .borrow))
        ])

        let borrowing = byAsset(valuation, .debt)

        let row = try #require(borrowing.rows.first)
        #expect(row.value == 40)
        #expect(row.totals.gross == 0)
        #expect(borrowing.total == 40)
    }

    @Test(arguments: [(Decimal(0), 0), (Decimal(1), 1), (Decimal(50), 3), (Decimal(-5), 0)])
    func `changing the threshold moves rows but never the total`(threshold: Decimal, hiddenRows: Int) {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("A", 100)),
            Fixture.input(Fixture.synced("B", 10)),
            Fixture.input(Fixture.synced("C", Fixture.decimal("0.5"))),
            Fixture.input(Fixture.synced("D", 5, role: .borrow))
        ])
        let settings = TokenDashboardSettings(minimumDashboardValue: threshold, hideUnpriced: true, hideDust: true)

        let list = Fixture.list(valuation, .net, settings: settings) { $0.token.assetId }
        let ranked = list.ranked()

        #expect(ranked.hidden.rowCount == hiddenRows)
        #expect(ranked.rows.count == 4 - hiddenRows)
        #expect(list.total == Fixture.decimal("105.5"))
        #expect(ranked.rows.reduce(0) { $0 + $1.value } + ranked.hidden.net == list.total)
    }

    @Test func `negative threshold hides nothing`() {
        let settings = TokenDashboardSettings(minimumDashboardValue: -5)

        #expect(settings.dustThresholdUSD == 0)
        #expect(TokenDashboardSettings.normalizedThreshold(-5) == 0)
        #expect(TokenDashboardSettings.normalizedThreshold(3) == 3)
    }

    @Test func `unpriced row contributes nothing and is hidden by hide unpriced`() throws {
        let unpriced = Fixture.token("UNP", coinGeckoId: "unp", amount: 10, usdValue: 0)
        let valuation = Fixture.valuation([Fixture.input(unpriced), Fixture.input(Fixture.synced("ETH", 100))])

        let list = byAsset(valuation, .net)

        let row = try #require(list.rows.first)
        #expect(row.status == .unpriced)
        #expect(row.value == 0)
        #expect(list.hidden.rowCount == 1)
        #expect(list.hidden.unpricedCount == 1)
        #expect(!list.hidden.isAllDust)
        #expect(list.total == 100)
    }

    @Test func `unpriced row is visible when hide unpriced is off even under hide dust`() throws {
        let unpriced = Fixture.token("UNP", coinGeckoId: "unp", amount: 10, usdValue: 0)
        let valuation = Fixture.valuation([Fixture.input(unpriced)])
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: false, hideDust: true)

        let list = Fixture.list(valuation, .net, settings: settings) { $0.token.assetId }

        let row = try #require(list.rows.first)
        #expect(row.status == .unpriced)
        #expect(row.isVisible)
        #expect(list.hidden.unpricedCount == 0)
        #expect(list.hidden.isEmpty)
    }

    @Test func `hidden summary reports count unpriced count and the three sums`() {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("DUST", Fixture.decimal("0.6"), assetId: assetId, role: .supply)),
            Fixture.input(Fixture.synced("DUST", Fixture.decimal("0.2"), assetId: assetId, role: .borrow)),
            Fixture.input(Fixture.token("UNP", coinGeckoId: "unp", amount: 1)),
            Fixture.input(Fixture.synced("LOAN", Fixture.decimal("0.3"), role: .borrow)),
            Fixture.input(Fixture.synced("ETH", 100))
        ])

        let hidden = byAsset(valuation, .net).hidden

        #expect(hidden.rowCount == 3)
        #expect(hidden.unpricedCount == 1)
        #expect(hidden.gross == Fixture.decimal("0.6"))
        #expect(hidden.debt == Fixture.decimal("0.5"))
        #expect(hidden.net == Fixture.decimal("0.1"))
        #expect(hidden.value(on: .debt) == Fixture.decimal("0.5"))
    }

    @Test func `hidden rows that are all dust read as small balances`() {
        let valuation = Fixture.valuation([Fixture.input(Fixture.synced("DUST", Fixture.decimal("0.6")))])

        let hidden = byAsset(valuation, .net).hidden

        #expect(hidden.rowCount == 1)
        #expect(hidden.isAllDust)
    }

    @Test func `two dusty tokens forming one row above the threshold stay visible`() throws {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", Fixture.decimal("0.6"), assetId: assetId)),
            Fixture.input(Fixture.synced("ETH", Fixture.decimal("0.6"), assetId: assetId))
        ])

        let row = try #require(byAsset(valuation, .net).rows.first)

        #expect(row.status == .priced)
        #expect(row.isVisible)
        #expect(row.value == Fixture.decimal("1.2"))
    }

    @Test func `matched supply and borrow is not dust on exposure`() throws {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 1000, assetId: assetId, role: .supply)),
            Fixture.input(Fixture.synced("ETH", 1000, assetId: assetId, role: .borrow))
        ])

        let row = try #require(byAsset(valuation, .net).rows.first)

        #expect(row.value == 0)
        #expect(row.status == .priced)
        #expect(row.isVisible)
    }

    @Test func `ignored asset with always show is not a dashboard row`() throws {
        let token = Fixture.synced("IGN", 500)
        let valuation = Fixture.valuation([Fixture.input(token)], overrides: [Fixture.ignore(token, alwaysShow: true)])

        let row = try #require(byAsset(valuation, .net).rows.first)

        #expect(row.status == .ignored)
        #expect(!row.alwaysShow)
        #expect(!row.isVisible)
    }

    @Test func `always show keeps a dust row and an unpriced row visible`() {
        let dust = Fixture.synced("DUST", Fixture.decimal("0.2"))
        let unpriced = Fixture.token("UNP", coinGeckoId: "unp", amount: 1)
        let valuation = Fixture.valuation(
            [Fixture.input(dust), Fixture.input(unpriced)],
            overrides: [Fixture.alwaysShow(dust), Fixture.alwaysShow(unpriced)])

        let list = byAsset(valuation, .net)

        #expect(list.rows.map(\.status) == [.dust, .unpriced])
        #expect(list.rows.map(\.alwaysShow) == [true, true])
        #expect(list.visibleRows.count == 2)
        #expect(list.hidden.isEmpty)
    }

    @Test(arguments: [GroupKey.category, .protocol])
    func `a reward from an always show asset does not make a dust row visible`(_ groupKey: GroupKey) throws {
        let dust = Fixture.synced("AAA", Fixture.decimal("0.5"))
        let reward = Fixture.token("BBB", coinGeckoId: "bbb", role: .reward, amount: 1, usdValue: 5)
        let valuation = Fixture.valuation(
            [Fixture.input(dust, protocolId: "aave"), Fixture.input(reward, protocolId: "aave")],
            overrides: [Fixture.alwaysShow(reward)])

        let list = Fixture.list(valuation, .net) { groupKey.key(of: $0) }
        let row = try #require(list.rows.first)

        #expect(list.rows.count == 1)
        #expect(row.status == .dust)
        #expect(!row.alwaysShow)
        #expect(!row.isVisible)
        #expect(list.hidden.rowCount == 1)
        #expect(list.hidden.gross == Fixture.decimal("0.5"))
    }

    @Test func `always show on one asset of a multi asset row keeps the row visible`() throws {
        let shown = Fixture.synced("AAA", Fixture.decimal("0.2"), portfolioCategory: Fixture.meme)
        let other = Fixture.synced("BBB", Fixture.decimal("0.3"), portfolioCategory: Fixture.meme)
        let valuation = Fixture.valuation(
            [Fixture.input(shown), Fixture.input(other)],
            overrides: [Fixture.alwaysShow(shown)])

        let list = Fixture.list(valuation, .net) { $0.token.portfolioCategory.id }
        let row = try #require(list.rows.first)

        #expect(list.rows.count == 1)
        #expect(row.status == .dust)
        #expect(row.alwaysShow)
        #expect(row.isVisible)
        #expect(list.hidden.isEmpty)
    }

    @Test func `dust row is visible when hide dust is off`() throws {
        let valuation = Fixture.valuation([Fixture.input(Fixture.synced("DUST", Fixture.decimal("0.2")))])
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: true, hideDust: false)

        let row = try #require(Fixture.list(valuation, .net, settings: settings) { $0.token.assetId }.rows.first)

        #expect(row.status == .dust)
        #expect(row.isVisible)
    }

    @Test func `ignored tokens do not decide the status of a mixed row`() throws {
        let ignored = Fixture.synced("IGN", 500)
        let unpriced = Fixture.token("UNP", coinGeckoId: "unp", amount: 1)
        let valuation = Fixture.valuation(
            [Fixture.input(ignored), Fixture.input(unpriced)],
            overrides: [Fixture.ignore(ignored)])

        let row = try #require(Fixture.list(valuation, .net) { _ in "slice" }.rows.first)

        #expect(row.status == .unpriced)
    }

    @Test func `token settings rows carry status and source for every asset`() throws {
        let synced = Fixture.synced("SYN", 40)
        let reward = Fixture.token("REW", coinGeckoId: "rew", role: .reward, amount: 1, usdValue: 5)
        let valuation = Fixture.valuation([Fixture.input(synced), Fixture.input(reward)])

        let rows = byAsset(valuation, .net).rows

        #expect(rows.map(\.status) == [.priced, .notCounted])
        let row = try #require(rows.first)
        #expect(row.pricing.source == .sync)
        #expect(row.value == 40)
    }

    private func byAsset(_ valuation: PortfolioValuation, _ basis: DashboardBasis) -> DashboardList<UUID> {
        Fixture.list(valuation, basis) { $0.token.assetId }
    }

    private func bySymbol(_ valuation: PortfolioValuation) -> DashboardList<String> {
        Fixture.list(valuation, .positiveNet) { "\($0.token.symbol)|\($0.token.name)" }
    }
}

enum GroupKey: String, CaseIterable, Sendable {
    case category
    case `protocol`

    func key(of token: ValuedToken) -> String {
        switch self {
        case .category: token.token.portfolioCategory.id.uuidString
        case .protocol: token.position.protocolId ?? ""
        }
    }
}
