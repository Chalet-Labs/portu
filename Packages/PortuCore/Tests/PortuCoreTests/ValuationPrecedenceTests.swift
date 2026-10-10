import Foundation
import PortuCore
import Testing

struct ValuationPrecedenceTests {
    private typealias Fixture = ValuationFixtures

    @Test func `valued tokens keep their position token id through display`() {
        let tokenId = UUID()
        let asset = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("ETH", 10, assetId: asset, role: .supply), tokenId: tokenId),
            Fixture.input(Fixture.synced("ETH", 4, assetId: asset, role: .borrow))
        ])

        #expect(valuation.tokens[0].tokenId == tokenId)
        #expect(valuation.tokens[0].display(rate: 2).tokenId == tokenId)
        #expect(valuation.tokens[1].tokenId != tokenId)
    }

    @Test func `manual price beats live close and sync`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2, usdValue: 9000)
        let override = Fixture.manual(token, price: 10)
        let market = Fixture.market(live: ["ethereum": 4000], closes: ["ethereum": Fixture.close(3900, day: 1)])

        let valued = Fixture.valued(token, market: market, overrides: [override])

        #expect(valued.source == .manual)
        #expect(valued.value == 20)
        #expect(valued.contribution == 20)
    }

    @Test func `live coin gecko price is never plausibility checked`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2, usdValue: 1)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["ethereum": 4000]))

        #expect(valued.source == .live)
        #expect(valued.value == 8000)
    }

    @Test func `plausible live onchain price is used`() {
        let identity = Fixture.onchain()
        let token = Fixture.token(onchainIdentity: identity, amount: 10, usdValue: 20)

        let valued = Fixture.valued(token, market: Fixture.market(live: [identity.historicalPriceID: 3]))

        #expect(valued.source == .live)
        #expect(valued.value == 30)
    }

    @Test func `implausible live onchain price leaves the token unpriced without falling back`() {
        let identity = Fixture.onchain()
        let token = Fixture.token(onchainIdentity: identity, amount: 10, usdValue: 20, syncedAt: Fixture.noon(-5))
        let market = Fixture.market(
            live: [identity.historicalPriceID: 1000],
            closes: [identity.historicalPriceID: Fixture.close(2, day: 0)])

        let valued = Fixture.valued(token, market: market)

        #expect(valued.source == .unpriced)
        #expect(valued.value == 0)
        #expect(valued.contribution == 0)
    }

    @Test func `implausible chosen onchain close leaves the token unpriced`() {
        let identity = Fixture.onchain()
        let token = Fixture.token(onchainIdentity: identity, amount: 10, usdValue: 20, syncedAt: Fixture.noon(-1))
        let market = Fixture.market(closes: [identity.historicalPriceID: Fixture.close(1000, day: 0)])

        let valued = Fixture.valued(token, market: market)

        #expect(valued.source == .unpriced)
        #expect(valued.value == 0)
    }

    @Test func `implausible close that loses to a newer sync gives the sync value`() {
        let identity = Fixture.onchain()
        let token = Fixture.token(onchainIdentity: identity, amount: 10, usdValue: 20, syncedAt: Fixture.noon(0))
        let market = Fixture.market(closes: [identity.historicalPriceID: Fixture.close(1000, day: -1)])

        let valued = Fixture.valued(token, market: market)

        #expect(valued.source == .sync)
        #expect(valued.value == 20)
    }

    @Test func `ignored asset is worth nothing whatever its prices`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2, usdValue: 9000)
        let override = TokenPricingOverrideSnapshot(assetId: token.assetId, manualPriceUSD: 10, isIgnored: true)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["ethereum": 4000]), overrides: [override])

        #expect(valued.source == .ignored)
        #expect(valued.value == 0)
        #expect(valued.contribution == 0)
        #expect(valued.isIgnored)
    }

    @Test func `ignored beats always show`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2)
        let valued = Fixture.valued(
            token,
            market: Fixture.market(live: ["ethereum": 4000]),
            overrides: [Fixture.ignore(token, alwaysShow: true)])

        #expect(valued.source == .ignored)
        #expect(!valued.alwaysShow)
    }

    @Test(arguments: [Decimal(0), Decimal(-1)])
    func `token without a positive amount is unpriced not counted and has no row`(amount: Decimal) {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: amount, usdValue: 500)
        let override = Fixture.manual(token, price: 10)
        let valuation = Fixture.valuation(
            [Fixture.input(token)],
            market: Fixture.market(live: ["ethereum": 4000]),
            overrides: [override])

        let valued = valuation.tokens[0]
        let list = Fixture.list(valuation, .net) { $0.token.assetId }

        #expect(valued.source == .unpriced)
        #expect(valued.value == 0)
        #expect(!valued.isCounted)
        #expect(list.rows.map(\.status) == [.notCounted])
        #expect(list.dashboardRows.isEmpty)
        #expect(list.hidden.isEmpty)
        #expect(valuation.totals.net == 0)
    }

    @Test func `ignored token with a positive amount is still counted`() {
        let token = Fixture.token(coinGeckoId: "ethereum", role: .supply, amount: 2)

        let valued = Fixture.valued(token, overrides: [Fixture.ignore(token)])

        #expect(valued.isCounted)
        #expect(!valued.isValued)
    }

    @Test func `borrow contributes its value negatively`() {
        let token = Fixture.token(coinGeckoId: "usd-coin", role: .borrow, amount: 500)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["usd-coin": 1]))

        #expect(valued.value == 500)
        #expect(valued.contribution == -500)
        #expect(valued.isCounted)
    }

    @Test func `reward keeps its value but contributes nothing and is not counted`() {
        let token = Fixture.token(coinGeckoId: "comp", role: .reward, amount: 2)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["comp": 50], changes: ["comp": 0.25]))

        #expect(valued.value == 100)
        #expect(valued.contribution == 0)
        #expect(valued.change24h == 0)
        #expect(!valued.isCounted)
    }

    @Test func `zero sync value is not a candidate`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2, usdValue: 0)

        #expect(Fixture.valued(token).source == .unpriced)
    }

    @Test func `zero sync value makes any onchain price plausible`() {
        let identity = Fixture.onchain()
        let token = Fixture.token(onchainIdentity: identity, amount: 1, usdValue: 0)

        let valued = Fixture.valued(token, market: Fixture.market(live: [identity.historicalPriceID: 1_000_000]))

        #expect(valued.source == .live)
        #expect(valued.value == 1_000_000)
    }

    @Test(arguments: [
        (ValuationFixtures.decimal("0.01"), ValuationSource.live),
        (Decimal(100), ValuationSource.live),
        (ValuationFixtures.decimal("0.0099"), ValuationSource.unpriced),
        (ValuationFixtures.decimal("100.01"), ValuationSource.unpriced)
    ])
    func `plausibility band is inclusive at 0.01 and 100`(price: Decimal, expected: ValuationSource) {
        let identity = Fixture.onchain()
        let token = Fixture.token(onchainIdentity: identity, amount: 1, usdValue: 1)

        let valued = Fixture.valued(token, market: Fixture.market(live: [identity.historicalPriceID: price]))

        #expect(valued.source == expected)
    }

    @Test(arguments: [(Decimal(3), ValuationSource.live, Decimal(30)), (Decimal(1000), ValuationSource.unpriced, Decimal(0))])
    func `plausibility measures against the magnitude of a negative sync value`(
        price: Decimal,
        expected: ValuationSource,
        value: Decimal) {
        let identity = Fixture.onchain()
        let token = Fixture.token(onchainIdentity: identity, amount: 10, usdValue: -20)

        let valued = Fixture.valued(token, market: Fixture.market(live: [identity.historicalPriceID: price]))

        #expect(valued.source == expected)
        #expect(valued.value == value)
    }
}

struct ValuationNewerOfTests {
    private typealias Fixture = ValuationFixtures

    @Test(arguments: [
        NewerOfCase("close on a later day than the sync wins", syncDay: -1, closeDay: 0, usdValue: 6000, source: .close, value: 7000),
        NewerOfCase("sync on the same day as the close wins", syncDay: 0, closeDay: 0, usdValue: 6000, source: .sync, value: 6000),
        NewerOfCase("sync on a later day than the close wins", syncDay: 0, closeDay: -2, usdValue: 6000, source: .sync, value: 6000),
        NewerOfCase("only a close is used", syncDay: 1, closeDay: -2, usdValue: 0, source: .close, value: 7000),
        NewerOfCase("missing sync time loses to a close", syncDay: nil, closeDay: -2, usdValue: 6000, source: .close, value: 7000)
    ])
    func `the newer of close and sync wins`(_ newerOf: NewerOfCase) {
        let token = Fixture.token(
            coinGeckoId: "ethereum",
            amount: 2,
            usdValue: newerOf.usdValue,
            syncedAt: newerOf.syncDay.map(Fixture.noon))

        let valued = Fixture.valued(
            token,
            market: Fixture.market(closes: ["ethereum": Fixture.close(3500, day: newerOf.closeDay)]))

        #expect(valued.source == newerOf.source)
        #expect(valued.value == newerOf.value)
    }

    @Test func `a close stamped later on the sync's own utc day loses to the sync`() {
        let token = Fixture.token(coinGeckoId: "bitcoin", amount: 1, usdValue: 100, syncedAt: Fixture.noon(0))
        let intraday = HistoricalClose(day: Fixture.noon(0).addingTimeInterval(3600), price: 200)

        let valued = Fixture.valued(token, market: Fixture.market(closes: ["bitcoin": intraday]))

        #expect(intraday.day == Fixture.day(0))
        #expect(valued.source == .sync)
        #expect(valued.value == 100)
    }

    @Test func `only a sync value is used even without a price id`() {
        let token = Fixture.token(coinGeckoId: nil, amount: 2, usdValue: 6000)

        let valued = Fixture.valued(token)

        #expect(valued.source == .sync)
        #expect(valued.value == 6000)
    }

    @Test func `sync value is taken as a magnitude`() {
        let token = Fixture.token(coinGeckoId: nil, amount: 2, usdValue: -6000)

        #expect(Fixture.valued(token).value == 6000)
    }

    @Test func `neither close nor sync leaves the token unpriced`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2, usdValue: 0)

        let valued = Fixture.valued(token, market: Fixture.market(closes: ["other": Fixture.close(1, day: 0)]))

        #expect(valued.source == .unpriced)
        #expect(valued.value == 0)
    }

    @Test(arguments: [
        ValuationFixtures.market(live: ["ethereum": 0]),
        ValuationFixtures.market(closes: ["ethereum": ValuationFixtures.close(0, day: 1)])
    ])
    func `a zero live price or close is no price and falls through to the sync value`(market: MarketPrices) {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 2, usdValue: 6000, syncedAt: Fixture.noon(0))

        let valued = Fixture.valued(token, market: market)

        #expect(valued.source == .sync)
        #expect(valued.value == 6000)
    }

    @Test func `live price beats a newer close`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 1, usdValue: 1, syncedAt: Fixture.noon(-3))

        let valued = Fixture.valued(
            token,
            market: Fixture.market(live: ["ethereum": 4000], closes: ["ethereum": Fixture.close(3500, day: 0)]))

        #expect(valued.source == .live)
        #expect(valued.value == 4000)
    }
}

struct NewerOfCase: CustomTestStringConvertible, Sendable {
    let name: String
    let syncDay: Int?
    let closeDay: Int
    let usdValue: Decimal
    let source: ValuationSource
    let value: Decimal

    init(_ name: String, syncDay: Int?, closeDay: Int, usdValue: Decimal, source: ValuationSource, value: Decimal) {
        self.name = name
        self.syncDay = syncDay
        self.closeDay = closeDay
        self.usdValue = usdValue
        self.source = source
        self.value = value
    }

    var testDescription: String {
        name
    }
}
