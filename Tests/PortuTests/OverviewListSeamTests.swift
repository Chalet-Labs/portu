import Foundation
@testable import Portu
import PortuCore
import Testing

/// T2 for the Overview lists fed the shared fixture: the position tabs, the Top Assets donut, the
/// watchlist, Health and the polling candidates. Each list is checked against its A7 identity.
struct OverviewListSeamTests {
    private typealias Fixture = OverviewValuationFixture

    // MARK: - Position tabs

    @Test func `idle stables group total is its visible rows plus its hidden line`() {
        let tab = OverviewPositionProjection.tab(.idleStables, context: Fixture.context(), positions: Fixture.positions)

        #expect(tab.groups.map(\.position.title) == ["Main Wallet"])
        #expect(tab.groups.map { $0.tokens.map(\.symbol) } == [["USDC"]])
        withKnownIssue("converges in step 5: S3/F3 — the Main Wallet group ends with its hidden dust line (DAI 0.5) and its change") {
            #expect(tab.groups.map(\.value) == [Fixture.decimal("1000.5")])
            #expect(tab.groups.map(\.change24h) == [Fixture.decimal("0.1")])
            #expect(tab.groups.first?.hidden?.rowCount == 1)
            #expect(tab.groups.first?.hidden?.isAllDust == true)
            #expect(tab.groups.first?.hidden?.gross == Fixture.decimal("0.5"))
            #expect(tab.total == Fixture.decimal("1000.5"))
        }
    }

    @Test func `idle majors tab shows idle majors with their exact change`() {
        let tab = OverviewPositionProjection.tab(.idleMajors, context: Fixture.context(), positions: Fixture.positions)

        #expect(tab.groups.map { $0.tokens.map(\.symbol) } == [["ETH"]])
        #expect(tab.total == 6000)
        withKnownIssue("converges in step 5: V4 — exact 24h formula") {
            #expect(tab.change24h == 1200)
        }
    }

    @Test func `borrowing group total is its visible debt plus its hidden line`() {
        let tab = OverviewPositionProjection.tab(.borrowing, context: Fixture.context(), positions: Fixture.positions)

        #expect(tab.groups.map(\.position.title) == ["Aave V3"])
        #expect(tab.groups.map { $0.tokens.map(\.symbol) } == [["ETH"]])
        withKnownIssue("converges in step 5: S3/F3/V4 — the Aave V3 group ends with its hidden dust borrow (USDT 0.4); exact change") {
            #expect(tab.groups.map(\.value) == [Fixture.decimal("-1500.4")])
            #expect(tab.groups.map(\.change24h) == [-300])
            #expect(tab.groups.first?.hidden?.rowCount == 1)
            #expect(tab.groups.first?.hidden?.debt == Fixture.decimal("0.4"))
            #expect(tab.total == Fixture.decimal("-1500.4"))
        }
    }

    @Test func `idle tab rows take the sync value under newer of`() {
        let stable = Fixture.input(101, .wallet, Fixture.token(
            Fixture.uuid(1001), "USDS", "Sky Dollar", .stablecoin, amount: 500, usdValue: 500))
        let major = Fixture.input(102, .wallet, Fixture.token(
            Fixture.uuid(1002), "BTC", "Bitcoin", .major, coinGeckoId: "bitcoin",
            amount: Fixture.decimal("0.01"), usdValue: 600, syncedAt: Fixture.noon(0)))
        let context = Fixture.context(
            inputs: [stable, major],
            livePricesUSD: [:],
            liveChanges24h: [:],
            historical: HistoricalMarketPrices(closesUSD: ["bitcoin": HistoricalClose(day: Fixture.day(0), price: 61000)]))
        let stables = OverviewPositionProjection.tab(.idleStables, context: context, positions: Fixture.positions)
        let majors = OverviewPositionProjection.tab(.idleMajors, context: context, positions: Fixture.positions)

        #expect(stable.token.portfolioCategory.semanticRole == .stablecoin)
        #expect(PortfolioCategoryDefaults.majorCategoryIDs.contains(major.token.portfolioCategory.id))
        #expect(majors.groups.flatMap(\.tokens).map(\.symbol) == ["BTC"])
        withKnownIssue("converges in step 5: V1.5/S3 — a sync-only stable shows its sync value; a same-day close loses to the sync") {
            #expect(stables.groups.flatMap(\.tokens).map(\.symbol) == ["USDS"])
            #expect(stables.groups.flatMap(\.tokens).map(\.value) == [500])
            #expect(stables.groups.flatMap(\.tokens).map(\.price) == [1])
            #expect(majors.groups.flatMap(\.tokens).map(\.value) == [600])
            #expect(majors.groups.flatMap(\.tokens).map(\.price) == [60000])
        }
    }

    @Test func `key changes rank the visible movers and their group totals are the shown rows`() {
        let tab = OverviewPositionProjection.tab(.keyChanges, context: Fixture.context(), positions: Fixture.positions)

        #expect(tab.groups.map(\.position.title) == ["Main Wallet", "Aave V3"])
        #expect(tab.groups.map { $0.tokens.map(\.symbol) } == [["ETH", "LINK", "PEPE"], ["ETH"]])
        #expect(tab.groups.map { $0.tokens.map(\.value) } == [[6000, 160, 10], [3000]])
        #expect(tab.groups.map(\.value) == [6170, 3000])
        #expect(tab.groups.allSatisfy { $0.hidden == nil })
        withKnownIssue("converges in step 5: V4/F5 — the exact change ranks and shows each mover") {
            #expect(tab.groups.map { $0.tokens.map(\.change24h) } == [[1200, 32, -10], [600]])
        }
    }

    /// One shared fraction keeps the rank by |change| the rank by value under today's formula and
    /// under V4 alike.
    @Test func `key changes show the top twenty movers with the symbol tie break and no hidden line`() {
        var movers: [(symbol: String, value: Decimal)] = (1 ... 20).map { (String(format: "K%02d", $0), Decimal(2100 - 100 * $0)) }
        movers += [("TIEA", 1050), ("TIEB", 1050)]
        // Reversed, so TIEB arrives first and only the symbol tie-break puts TIEA ahead.
        let inputs = movers.enumerated().reversed().map { index, mover in
            Fixture.input(200 + index, .wallet, Fixture.token(
                Fixture.uuid(2000 + index), mover.symbol, mover.symbol, .defi, coinGeckoId: mover.symbol.lowercased(),
                amount: 1, usdValue: mover.value))
        }
        let context = Fixture.context(
            inputs: inputs,
            livePricesUSD: Dictionary(uniqueKeysWithValues: movers.map { ($0.symbol.lowercased(), $0.value) }),
            liveChanges24h: Dictionary(uniqueKeysWithValues: movers.map { ($0.symbol.lowercased(), Fixture.decimal("0.1")) }),
            historical: .empty)

        let tab = OverviewPositionProjection.tab(.keyChanges, context: context, positions: Fixture.positions)

        #expect(tab.groups.map(\.position.title) == ["Main Wallet"])
        #expect(tab.groups.flatMap(\.tokens).map(\.symbol) == [
            "K01", "K02", "K03", "K04", "K05", "K06", "K07", "K08", "K09", "K10",
            "TIEA", "TIEB",
            "K11", "K12", "K13", "K14", "K15", "K16", "K17", "K18"
        ])
        #expect(tab.groups.map(\.value) == [22800])
        #expect(tab.groups.allSatisfy { $0.hidden == nil })
    }

    // MARK: - Top Assets donut

    @Test func `top assets slices plus other plus hidden equal gross assets`() {
        let topAssets = OverviewFeature.topAssets(.assets, context: Fixture.context())

        #expect(topAssets.slices.prefix(3).map(\.label) == ["ETH", "SOL", "USDC"])
        #expect(topAssets.slices.prefix(3).map(\.value) == [9000, 1500, 1000])
        withKnownIssue("converges in step 5: F5/A7 — the sync-only OTC ranks, the hidden line (dust DAI, unpriced BAD) closes the total") {
            #expect(topAssets.slices.map(\.label) == ["ETH", "SOL", "USDC", "OTC", "LINK", "other"])
            #expect(topAssets.slices.map(\.value) == [9000, 1500, 1000, 250, 160, Fixture.decimal("370.3")])
            #expect(topAssets.hidden?.rowCount == 2)
            #expect(topAssets.hidden?.unpricedCount == 1)
            #expect(topAssets.hidden?.gross == Fixture.decimal("0.5"))
            #expect(topAssets.hiddenDisplayPercent == 0)
            let gross = topAssets.slices.reduce(Decimal.zero) { $0 + $1.value } + (topAssets.hidden?.gross ?? 0)
            #expect(gross == Fixture.decimal("12280.8"))
        }
    }

    @Test func `category slices are gross per category`() {
        let topAssets = OverviewFeature.topAssets(.category, context: Fixture.context())

        #expect(topAssets.slices.prefix(2).map(\.label) == ["ETH", "SOL"])
        #expect(topAssets.slices.first { $0.label == "Meme" }?.value == 110)
        withKnownIssue("converges in step 5: F2/A7 — dust is judged per category row, sync values count, same-day sync wins") {
            #expect(topAssets.slices.map(\.label) == ["ETH", "SOL", "Stablecoins", "Other Tokens", "DeFi", "Meme"])
            #expect(topAssets.slices.map(\.value) == [
                9000, 1500, Fixture.decimal("1000.5"), Fixture.decimal("340.3"), 330, 110
            ])
            #expect(topAssets.slices.reduce(Decimal.zero) { $0 + $1.value } == Fixture.decimal("12280.8"))
        }
    }

    // MARK: - Watchlist

    @Test func `watchlist held rows show the row price and unheld coins show live else close`() throws {
        let rows = watchlist()

        let eth = try #require(rows.first { $0.symbol == "ETH" })
        #expect(eth.price == 3000)
        #expect(eth.change24h == Fixture.decimal("0.25"))
        let manual = try #require(rows.first { $0.symbol == "MNL" })
        #expect(manual.price == 2)
        #expect(manual.change24h == nil)
        let link = try #require(rows.first { $0.symbol == "LINK" })
        #expect(link.price == 16)
        #expect(link.change24h == Fixture.decimal("0.25"))
        #expect(rows.suffix(2).map(\.id) == ["bitcoin", "dogecoin"])
        #expect(rows.suffix(2).map(\.price) == [60000, Fixture.decimal("0.2")])
        #expect(rows.suffix(2).map(\.change24h) == [Fixture.decimal("0.1"), Fixture.decimal("-0.2")])
        #expect(!rows.contains { ["SCAM", "BAD", "DAI"].contains($0.symbol) })
        withKnownIssue("converges in step 5: S3/F5/V5 — held rows rank by module value and show Σ value ÷ Σ amount") {
            #expect(Set(rows.dropLast(2).map(\.symbol)) == ["ETH", "SOL", "USDC", "OTC", "LINK", "MNL", "DEGEN", "ARB", "UNI", "PEPE"])
            #expect(rows.first { $0.symbol == "UNI" }?.price == 7)
            #expect(rows.first { $0.symbol == "OTC" }?.price == 50)
        }
    }

    @Test func `watchlist prices are converted once at a non usd rate`() {
        let rows = watchlist(rate: Fixture.decimal("0.9"))
        let price = { (symbol: String) in rows.first { $0.symbol == symbol }?.price }

        #expect(price("ETH") == 2700)
        #expect(price("MNL") == Fixture.decimal("1.8"))
        #expect(price("LINK") == Fixture.decimal("14.4"))
        #expect(price("bitcoin") == 54000)
        #expect(price("dogecoin") == Fixture.decimal("0.18"))
    }

    // MARK: - Health

    @Test func `health weights are shares of the floored asset nets`() throws {
        let health = PortfolioHealthFeature.health(Fixture.context(), legacyChainCount: Fixture.legacyChainCount)

        let eth = try #require(health.weights.first { $0.symbol == "ETH" })
        #expect(eth.usdValue == 7500)
        #expect(!health.weights.contains { ["DAI", "USDT", "SCAM", "BAD"].contains($0.symbol) })
        withKnownIssue("converges in step 5: S3/F1 — every valued asset counts, floored at 0, with the dust line hidden") {
            #expect(eth.percentage == 7500 / Fixture.decimal("10780.8"))
            #expect(Set(health.weights.map(\.symbol)) == [
                "USDC", "ETH", "PEPE", "MNL", "LINK", "UNI", "TINY", "DEGEN", "OTC", "SOL", "ARB"
            ])
            #expect(health.hidden?.gross == Fixture.decimal("0.5"))
            #expect(health.hiddenShare == Fixture.decimal("0.5") / Fixture.decimal("10780.8"))
            let total = health.weights.reduce(Decimal.zero) { $0 + $1.usdValue } + (health.hidden?.net ?? 0)
            #expect(total == Fixture.decimal("10780.8"))
        }
    }

    @Test func `health metrics cover every valued asset in active accounts`() {
        let health = PortfolioHealthFeature.health(Fixture.context(), legacyChainCount: Fixture.legacyChainCount)

        withKnownIssue("converges in step 5: S3 — metrics include dust and sync values; chainCount drops ignored-only chains") {
            #expect(health.metrics.assetCount == 12)
            #expect(health.metrics.chainCount == 4)
            #expect(health.metrics.stablecoinRatio == Fixture.decimal("1000.5") / Fixture.decimal("10780.8"))
        }
    }

    // MARK: - Polling candidates (characterization, S12)

    @Test func `polling keeps an implausible onchain token ranked by its sync value`() {
        let ids = OverviewFeature.pricePollingIDs(Fixture.context(), watchlistIDs: Fixture.watchlistIDs, portfolioLimit: 3)

        #expect(ids == ["ethereum", Fixture.badIdentity.historicalPriceID, "solana", "bitcoin", "dogecoin"])
    }

    @Test func `polling never selects an ignored token however large its sync value`() {
        let ids = OverviewFeature.pricePollingIDs(Fixture.context(), watchlistIDs: Fixture.watchlistIDs)

        #expect(ids.contains(Fixture.badIdentity.historicalPriceID))
        #expect(!ids.contains("scam-token"))
    }

    private func watchlist(rate: Decimal = 1) -> [OverviewPriceRowData] {
        OverviewFeature.watchlistRows(
            Fixture.context(rate: rate),
            assetsByCoinGeckoId: [:],
            watchlistIDs: Fixture.watchlistIDs)
    }
}

// MARK: - Seam wiring that holds today and per spec

extension OverviewListSeamTests {
    @Test(arguments: OverviewPositionTab.allCases)
    func `position tabs scale linearly with the display rate`(tab: OverviewPositionTab) {
        let rate = Fixture.decimal("0.9")
        let usd = OverviewPositionProjection.tab(tab, context: Fixture.context(), positions: Fixture.positions)
        let display = OverviewPositionProjection.tab(tab, context: Fixture.context(rate: rate), positions: Fixture.positions)

        #expect(!usd.groups.isEmpty)
        #expect(display.groups.map { $0.tokens.map(\.symbol) } == usd.groups.map { $0.tokens.map(\.symbol) })
        #expect(display.groups.map { $0.tokens.map(\.price) } == usd.groups.map { $0.tokens.map { $0.price * rate } })
        #expect(display.groups.map { $0.tokens.map(\.value) } == usd.groups.map { $0.tokens.map { $0.value * rate } })
        #expect(display.groups.map { $0.tokens.map(\.change24h) } == usd.groups.map { $0.tokens.map { $0.change24h * rate } })
        #expect(display.groups.map(\.value) == usd.groups.map { $0.value * rate })
    }

    @Test func `key changes price a mapped token through its mapping and never show an ignored one`() {
        var changes = Fixture.liveChanges24h
        changes["degen-base"] = Fixture.decimal("0.1")
        changes["scam-token"] = Fixture.decimal("0.5")
        let tab = OverviewPositionProjection.tab(
            .keyChanges,
            context: Fixture.context(liveChanges24h: changes),
            positions: Fixture.positions)
        let rows = tab.groups.flatMap(\.tokens)

        #expect(rows.first { $0.symbol == "DEGEN" }?.value == 100)
        #expect(!rows.contains { $0.symbol == "SCAM" })
    }

    @Test func `top assets keep five ranked slices plus other and shares that sum to one hundred`() {
        let topAssets = OverviewFeature.topAssets(.assets, context: Fixture.context())

        #expect(topAssets.slices.count == 6)
        #expect(topAssets.slices.last?.label == "other")
        #expect(topAssets.slices.reduce(0) { $0 + $1.displayPercent } + (topAssets.hiddenDisplayPercent ?? 0) == 100)
    }

    @Test(arguments: [TopAssetMode.assets, .category])
    func `top assets scale linearly with the display rate`(mode: TopAssetMode) {
        let rate = Fixture.decimal("0.9")
        let usd = OverviewFeature.topAssets(mode, context: Fixture.context())
        let display = OverviewFeature.topAssets(mode, context: Fixture.context(rate: rate))

        #expect(display.slices.map(\.label) == usd.slices.map(\.label))
        #expect(display.slices.map(\.value) == usd.slices.map { $0.value * rate })
        #expect(display.slices.map(\.displayPercent) == usd.slices.map(\.displayPercent))
    }

    @Test func `health weights scale with the display rate`() throws {
        let rate = Fixture.decimal("0.9")
        let usd = PortfolioHealthFeature.health(Fixture.context(), legacyChainCount: Fixture.legacyChainCount)
        let display = PortfolioHealthFeature.health(Fixture.context(rate: rate), legacyChainCount: Fixture.legacyChainCount)

        let eth = try #require(display.weights.first { $0.symbol == "ETH" })
        #expect(eth.usdValue == 6750)
        #expect(display.weights.map(\.symbol) == usd.weights.map(\.symbol))
        #expect(display.weights.map(\.usdValue) == usd.weights.map { $0.usdValue * rate })
    }

    @Test func `polling asks for a mapped token by its mapped id`() {
        let ids = OverviewFeature.pricePollingIDs(Fixture.context(), watchlistIDs: [])

        #expect(ids.contains("degen-base"))
        #expect(!ids.contains(Fixture.degenIdentity.historicalPriceID))
    }
}
