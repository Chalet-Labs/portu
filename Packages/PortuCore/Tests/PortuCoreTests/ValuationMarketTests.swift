import Foundation
import PortuCore
import Testing

struct ValuationMarketTests {
    private typealias Fixture = ValuationFixtures

    @Test func `closes keep only usd rows and the latest day per price id`() {
        let rows = [
            Fixture.closeRow("ethereum", 3000, day: -2),
            Fixture.closeRow("ethereum", 3100, day: -1),
            Fixture.closeRow("ethereum", 9999, day: 0, currency: .eur),
            Fixture.closeRow("bitcoin", 60000, day: 0, currency: .chf),
            Fixture.closeRow(" USD-Coin ", 1, day: 0)
        ]

        let closes = MarketPrices.latestCloses(from: rows)

        #expect(closes["ethereum"] == HistoricalClose(day: Fixture.day(-1), price: 3100))
        #expect(closes["bitcoin"] == nil)
        #expect(closes["usd-coin"] == HistoricalClose(day: Fixture.day(0), price: 1))
    }

    @Test(arguments: [false, true])
    func `same day closes keep the higher price whatever the row order`(reversed: Bool) throws {
        let rows = [Fixture.closeRow("ethereum", 3000, day: 0), Fixture.closeRow("ethereum", 3100, day: 0)]

        let close = try #require(MarketPrices.latestCloses(from: reversed ? rows.reversed() : rows)["ethereum"])

        #expect(close.price == 3100)
    }

    @Test func `closes are empty when historical backfill is disabled`() {
        let market = MarketPrices(
            liveUSD: ["ethereum": 4000],
            liveChanges24h: ["ethereum": Fixture.decimal("0.05")],
            closeRows: [
                Fixture.closeRow("ethereum", 3000, day: -1),
                Fixture.closeRow("ethereum", 3300, day: 0),
                Fixture.closeRow("bitcoin", 100, day: -1),
                Fixture.closeRow("bitcoin", 110, day: 0)
            ],
            isBackfillEnabled: false,
            now: Fixture.noon(0))

        #expect(market.closesUSD.isEmpty)
        #expect(market.changes24h == ["ethereum": Fixture.decimal("0.05")])
        #expect(market.liveUSD == ["ethereum": 4000])
    }

    @Test func `closes outside the two day window are dropped`() throws {
        let market = MarketPrices(
            liveUSD: [:],
            liveChanges24h: [:],
            closeRows: [
                Fixture.closeRow("old", 4, day: -4),
                Fixture.closeRow("old", 5, day: -3),
                Fixture.closeRow("recent", 7, day: -2)
            ],
            isBackfillEnabled: true,
            now: Fixture.noon(0))

        #expect(MarketPrices.closeWindowStart(now: Fixture.noon(0)) == Fixture.day(-2))
        #expect(market.closesUSD["old"] == nil)
        #expect(market.changes24h["old"] == nil)
        #expect(try #require(market.closesUSD["recent"]).price == 7)
    }

    @Test func `historical fraction comes from two consecutive usd days`() {
        let rows = [
            Fixture.closeRow("ethereum", 1000, day: -2),
            Fixture.closeRow("ethereum", 1000, day: -1),
            Fixture.closeRow("ethereum", 1100, day: 0),
            Fixture.closeRow("ethereum", 5000, day: -1, currency: .eur)
        ]

        #expect(MarketPrices.changes24h(from: rows)["ethereum"] == Fixture.decimal("0.1"))
    }

    @Test(arguments: [false, true])
    func `same day duplicate closes give the fraction of the higher price whatever the row order`(reversed: Bool) {
        let today = [Fixture.closeRow("ethereum", 1000, day: 0), Fixture.closeRow("ethereum", 1100, day: 0)]
        let rows = [Fixture.closeRow("ethereum", 1000, day: -1)] + (reversed ? today.reversed() : today)

        #expect(MarketPrices.changes24h(from: rows)["ethereum"] == Fixture.decimal("0.1"))
    }

    @Test func `latest closes that are not on consecutive days give no fraction`() {
        let rows = [
            Fixture.closeRow("ethereum", 1000, day: -2),
            Fixture.closeRow("ethereum", 1100, day: 0)
        ]

        #expect(MarketPrices.changes24h(from: rows)["ethereum"] == nil)
    }

    @Test func `live fractions are merged over historical ones`() {
        let merged = MarketPrices.mergedChanges24h(
            live: ["ethereum": Fixture.decimal("0.2")],
            historical: ["ethereum": Fixture.decimal("0.1"), "bitcoin": Fixture.decimal("0.05")])

        #expect(merged == ["ethereum": Fixture.decimal("0.2"), "bitcoin": Fixture.decimal("0.05")])
    }

    @Test func `quote prefers the live price then the close and carries the merged fraction`() {
        let market = Fixture.market(
            live: ["ethereum": 4000],
            closes: ["ethereum": Fixture.close(3900, day: 0), "bitcoin": Fixture.close(60000, day: 0)],
            changes: ["bitcoin": Fixture.decimal("0.05")])

        #expect(market.quote(priceID: "ethereum") == RowPricing(price: 4000, source: .live, fraction24h: nil))
        #expect(market.quote(priceID: " Bitcoin ") == RowPricing(price: 60000, source: .close, fraction24h: Fixture.decimal("0.05")))
        #expect(market.quote(priceID: "missing") == RowPricing(price: nil, source: nil, fraction24h: nil))
        #expect(market.quote(priceID: "bitcoin").display(rate: 2).price == 120_000)
    }

    @Test func `book keys are normalized like price ids`() {
        let market = Fixture.market(live: [" Ethereum ": 4000])

        let valued = Fixture.valued(Fixture.token(coinGeckoId: "ethereum", amount: 1), market: market)

        #expect(valued.value == 4000)
    }

    @Test func `historical close rows project the currency and keep the day`() {
        let row = HistoricalCloseRow(priceID: "ethereum", day: Fixture.noon(-1), currency: .eur, price: 10)

        #expect(row.day == Fixture.day(-1))
        #expect(row.currency == .eur)
    }
}

struct ValuationUnitsTests {
    private typealias Fixture = ValuationFixtures

    @Test func `a non usd rate is applied once after valuation`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2, usdValue: 1)
        let manual = Fixture.token("MAN", coinGeckoId: "man", amount: 3)
        let synced = Fixture.synced("SYN", 40)
        let valuation = Fixture.valuation(
            [Fixture.input(token), Fixture.input(manual), Fixture.input(synced)],
            market: Fixture.market(live: ["ethereum": 100]),
            overrides: [Fixture.manual(manual, price: 10)])

        let display = valuation.totals.display(rate: Fixture.decimal("0.9"))

        #expect(valuation.totals.net == 270)
        #expect(display.net == 243)
        #expect(valuation.tokens.map { $0.display(rate: Fixture.decimal("0.9")).value } == [180, 27, 36])
    }
}
