import Foundation
import PortuCore
import Testing

struct ValuationAggregateTests {
    private typealias Fixture = ValuationFixtures

    @Test func `net total sums every contribution including dust and small borrows`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.token("ETH", coinGeckoId: "ethereum", amount: 1)),
            Fixture.input(Fixture.token("DUST", coinGeckoId: "dust", amount: 1)),
            Fixture.input(Fixture.token("USDC", coinGeckoId: "usd-coin", role: .borrow, amount: Decimal(1) / 2))
        ], market: Fixture.market(live: ["ethereum": 4000, "dust": Decimal(1) / 4, "usd-coin": 1]))

        #expect(valuation.totals.gross == Decimal(400_025) / 100)
        #expect(valuation.totals.debt == Decimal(1) / 2)
        #expect(valuation.totals.net == Decimal(399_975) / 100)
    }

    @Test func `a section equals the sum of its cards`() throws {
        let aave = UUID()
        let morpho = UUID()
        let inputs = [
            Fixture.input(Fixture.token("ETH", coinGeckoId: "ethereum", role: .supply, amount: 2), positionId: aave, protocolId: "aave"),
            Fixture.input(Fixture.token("USDC", coinGeckoId: "usd-coin", role: .borrow, amount: 1000), positionId: aave, protocolId: "aave"),
            Fixture.input(Fixture.token("AAVE", coinGeckoId: "aave", role: .reward, amount: 1), positionId: aave, protocolId: "aave"),
            Fixture.input(Fixture.token("WBTC", coinGeckoId: "bitcoin", role: .supply, amount: 1), positionId: morpho, protocolId: "aave")
        ]
        let valuation = Fixture.valuation(
            inputs,
            market: Fixture.market(live: ["ethereum": 4000, "usd-coin": 1, "aave": 300, "bitcoin": 60000]))

        let cards = valuation.totals(groupedBy: { $0.position.positionId })
        let sections = valuation.totals(groupedBy: { $0.position.protocolId })

        let section = try #require(sections["aave"])
        #expect(try #require(cards[aave]).net == 7000)
        #expect(try #require(cards[morpho]).net == 60000)
        #expect(section.net == cards.values.reduce(0) { $0 + $1.net })
        #expect(section.net == valuation.totals.net)
    }

    @Test func `a manually priced token has the same value on the positions and overview paths`() throws {
        let positionId = UUID()
        let token = Fixture.token("XYZ", coinGeckoId: "xyz", amount: 4, usdValue: 1)
        let valuation = Fixture.valuation(
            [Fixture.input(token, positionId: positionId)],
            market: Fixture.market(live: ["xyz": 100]),
            overrides: [Fixture.manual(token, price: 5)])

        let card = try #require(valuation.totals(groupedBy: { $0.position.positionId })[positionId])
        let assetRow = try #require(Fixture.list(valuation, .net) { $0.token.assetId }.rows.first)

        #expect(card.net == 20)
        #expect(valuation.totals.net == 20)
        #expect(assetRow.totals.net == 20)
    }

    @Test(arguments: [true, false])
    func `idle plus deployed minus debt equals the net total`(withLivePrices: Bool) {
        let inputs = summaryCardInputs()
        let live: [String: Decimal] = withLivePrices
            ? ["usd-coin": 1, "ethereum": 4100, "pepe": Decimal(1) / 4, "steth": 4050]
            : [:]
        let valuation = Fixture.valuation(inputs, market: Fixture.market(live: live))

        let cards = valuation.summaryCards

        #expect(cards.idle.total + cards.deployed.total - cards.debt == valuation.totals.net)
        #expect(cards.debt == valuation.totals.debt)
        #expect(valuation.totals.net == (withLivePrices ? Fixture.decimal("8620.25") : Fixture.decimal("8460.25")))
        #expect(cards.deployed.other == 70)
    }

    @Test func `summary cards split idle by category and deployed by position type`() {
        let valuation = Fixture.valuation(
            summaryCardInputs(),
            market: Fixture.market(live: ["usd-coin": 1, "ethereum": 4000, "pepe": Decimal(1) / 4, "steth": 3990]))

        let cards = valuation.summaryCards

        #expect(cards.idle.stablecoinsAndFiat == 150)
        #expect(cards.idle.majors == 4000)
        #expect(cards.idle.tokensAndMemecoins == Decimal(1) / 4)
        #expect(cards.deployed.lending == 500)
        #expect(cards.deployed.staked == 3990)
        #expect(cards.deployed.yield == 150)
        #expect(cards.deployed.other == 70)
        #expect(cards.debt == 400)
    }

    @Test func `a negative net portfolio is reported as negative`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.token("ETH", coinGeckoId: "ethereum", role: .supply, amount: 1), positionType: .lending),
            Fixture.input(Fixture.token("USDC", coinGeckoId: "usd-coin", role: .borrow, amount: 300), positionType: .lending)
        ], market: Fixture.market(live: ["ethereum": 100, "usd-coin": 1]))

        #expect(valuation.totals.gross == 100)
        #expect(valuation.totals.debt == 300)
        #expect(valuation.totals.net == -200)
        #expect(valuation.summaryCards.deployed.total - valuation.summaryCards.debt == -200)
    }

    @Test func `grouped totals carry the role signed amount`() throws {
        let assetId = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.token("ETH", assetId: assetId, coinGeckoId: "ethereum", role: .supply, amount: 10), chain: .ethereum),
            Fixture.input(Fixture.token("ETH", assetId: assetId, coinGeckoId: "ethereum", role: .borrow, amount: 4), chain: .ethereum),
            Fixture.input(Fixture.token("ETH", assetId: assetId, coinGeckoId: "ethereum", role: .reward, amount: 1), chain: .ethereum),
            Fixture.input(Fixture.token("ETH", assetId: assetId, coinGeckoId: "ethereum", amount: 1), chain: .base)
        ], market: Fixture.market(live: ["ethereum": 10]))

        let byChain = valuation.totals(groupedBy: { $0.position.chain })

        let ethereum = try #require(byChain[.ethereum])
        #expect(ethereum.netAmount == 6)
        #expect(ethereum.net == 60)
        #expect(try #require(byChain[.base]).netAmount == 1)
    }

    @Test func `subset totals only cover matching tokens`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.token("ETH", coinGeckoId: "ethereum", amount: 1), positionType: .idle),
            Fixture.input(Fixture.token("ETH", coinGeckoId: "ethereum", amount: 2), positionType: .staking)
        ], market: Fixture.market(live: ["ethereum": 10]))

        #expect(valuation.totals(where: { $0.position.positionType == .idle }).net == 10)
    }

    @Test func `sync time total is the signed raw usd value sum`() {
        let ignored = Fixture.token("SCAM", usdValue: 50)
        let tokens = [
            Fixture.token("ETH", usdValue: 100),
            Fixture.token("USDC", role: .borrow, usdValue: 30),
            Fixture.token("COMP", role: .reward, usdValue: 5),
            Fixture.token("EMPTY", amount: 0, usdValue: 7),
            ignored
        ]
        let override = Fixture.ignore(ignored)

        #expect(PortfolioValuation.syncTimeTotal(of: tokens) == 127)
        #expect(PortfolioValuation.syncTimeTotal(of: tokens, excludingIgnoredIn: [override]) == 77)
    }

    @Test func `sync time cards split the raw total like the summary cards and reconcile with it`() {
        let ignored = Fixture.token("SCAM", usdValue: 50)
        let inputs = summaryCardInputs() + [
            Fixture.input(ignored, positionType: .staking),
            Fixture.input(Fixture.token("EMPTY", amount: 0, usdValue: 7), positionType: .vesting)
        ]
        let overrides = [Fixture.ignore(ignored)]

        let cards = SummaryCards.syncTime(of: inputs, excludingIgnoredIn: overrides)
        let total = PortfolioValuation.syncTimeTotal(of: inputs.map(\.token), excludingIgnoredIn: overrides)

        #expect(cards.idle.total + cards.deployed.total - cards.debt == total)
        #expect(total == Fixture.decimal("8467.25"))
        #expect(cards.idle.stablecoinsAndFiat == 150)
        #expect(cards.deployed.staked == 3990)
        #expect(cards.deployed.yield == 150)
        #expect(cards.deployed.other == 77)
        #expect(cards.debt == 400)
    }

    @Test func `sync time recording ignores an asset only when its applying override does`() throws {
        let token = Fixture.synced("ETH", 100)
        let applying = try TokenPricingOverrideSnapshot(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            assetId: token.assetId)
        let shadowed = try TokenPricingOverrideSnapshot(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            assetId: token.assetId,
            isIgnored: true)
        let overrides = [shadowed, applying]
        let inputs = [Fixture.input(token)]

        let valued = Fixture.valuation(inputs, overrides: overrides).tokens[0]

        #expect(!valued.isIgnored)
        #expect(PortfolioValuation.syncTimeTotal(of: [token], excludingIgnoredIn: overrides) == 100)
        #expect(SummaryCards.syncTime(of: inputs, excludingIgnoredIn: overrides).idle.total == 100)
    }

    @Test func `sync time total per account is raw and ignores the ignore flag`() throws {
        let account = UUID()
        let ignored = Fixture.token("SCAM", coinGeckoId: "scam", amount: 1, usdValue: 50)
        let valuation = Fixture.valuation(
            [
                Fixture.input(Fixture.token("ETH", coinGeckoId: "ethereum", amount: 1, usdValue: 100), accountId: account),
                Fixture.input(Fixture.token("COMP", role: .reward, usdValue: 5), accountId: account),
                Fixture.input(ignored, accountId: account)
            ],
            market: Fixture.market(live: ["ethereum": 4000]),
            overrides: [Fixture.ignore(ignored)])

        let totals = try #require(valuation.totals(groupedBy: { $0.position.accountId })[account])

        #expect(totals.net == 4000)
        #expect(totals.syncTotal == 150)
        #expect(totals.display(rate: 2).syncTotal == 300)
    }

    @Test func `selection value falls back to the sync value and never selects ignored tokens`() {
        let identity = Fixture.onchain()
        let implausible = Fixture.token(onchainIdentity: identity, amount: 1, usdValue: 20)
        let priced = Fixture.token(coinGeckoId: "ethereum", amount: 1, usdValue: 1)
        let ignored = Fixture.token(coinGeckoId: "scam", amount: 1, usdValue: 1_000_000)
        let valuation = Fixture.valuation(
            [Fixture.input(implausible), Fixture.input(priced), Fixture.input(ignored)],
            market: Fixture.market(live: [identity.historicalPriceID: 5000, "ethereum": 4000, "scam": 1]),
            overrides: [Fixture.ignore(ignored)])

        #expect(valuation.tokens.map(\.selectionValue) == [20, 4000, nil])
    }

    private func summaryCardInputs() -> [ValuationInput] {
        [
            Fixture.input(Fixture.token("USDC", portfolioCategory: Fixture.stablecoins, coinGeckoId: "usd-coin", amount: 100, usdValue: 100)),
            Fixture.input(Fixture.token("EUR", portfolioCategory: Fixture.fiat, amount: 50, usdValue: 50)),
            Fixture.input(Fixture.token("ETH", portfolioCategory: Fixture.eth, coinGeckoId: "ethereum", amount: 1, usdValue: 4000)),
            Fixture.input(Fixture.token(
                "PEPE",
                portfolioCategory: Fixture.meme,
                coinGeckoId: "pepe",
                amount: 1,
                usdValue: Decimal(1) / 4)),
            Fixture.input(
                Fixture.token("USDC", coinGeckoId: "usd-coin", role: .supply, amount: 500, usdValue: 500),
                positionType: .lending),
            Fixture.input(
                Fixture.token("USDC", coinGeckoId: "usd-coin", role: .borrow, amount: 400, usdValue: 400),
                positionType: .lending),
            Fixture.input(Fixture.token("STETH", coinGeckoId: "steth", role: .stake, amount: 1, usdValue: 3990), positionType: .staking),
            Fixture.input(Fixture.token("USDC", coinGeckoId: "usd-coin", role: .supply, amount: 100, usdValue: 100), positionType: .farming),
            Fixture.input(Fixture.token("COMP", coinGeckoId: "comp", role: .reward, amount: 1, usdValue: 60), positionType: .farming),
            Fixture.input(Fixture.token("LP", role: .lpToken, amount: 1, usdValue: 50), positionType: .liquidityPool),
            Fixture.input(Fixture.token("VEST", role: .balance, amount: 1, usdValue: 40), positionType: .vesting),
            Fixture.input(Fixture.token("MISC", role: .balance, amount: 1, usdValue: 30), positionType: .other)
        ]
    }
}

struct ValuationChangeTests {
    private typealias Fixture = ValuationFixtures
    private let tenth = Decimal(1) / 10

    @Test func `change is the exact move against the price a day ago`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 1)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["ethereum": 1100], changes: ["ethereum": tenth]))

        #expect(valued.change24h == 100)
        #expect(valued.fraction24h == tenth)
    }

    @Test func `borrow change is signed like its contribution`() {
        let token = Fixture.token(coinGeckoId: "ethereum", role: .borrow, amount: 1)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["ethereum": 1100], changes: ["ethereum": tenth]))

        #expect(valued.change24h == -100)
    }

    @Test func `sync source change is estimated from the market fraction`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 1, usdValue: 1100)

        let valued = Fixture.valued(token, market: Fixture.market(changes: ["ethereum": tenth]))

        #expect(valued.source == .sync)
        #expect(valued.change24h == 100)
    }

    @Test func `manual ignored unpriced and reward tokens have no change`() {
        let manual = Fixture.token("MAN", coinGeckoId: "man", amount: 1)
        let ignored = Fixture.token("IGN", coinGeckoId: "ign", amount: 1)
        let unpriced = Fixture.token("UNP", coinGeckoId: "unp", amount: 1)
        let reward = Fixture.token("REW", coinGeckoId: "rew", role: .reward, amount: 1)
        let valuation = Fixture.valuation(
            [manual, ignored, unpriced, reward].map { Fixture.input($0) },
            market: Fixture.market(
                live: ["man": 10, "ign": 10, "rew": 10],
                changes: ["man": tenth, "ign": tenth, "unp": tenth, "rew": tenth]),
            overrides: [Fixture.manual(manual, price: 10), Fixture.ignore(ignored)])

        #expect(valuation.tokens.map(\.change24h) == [0, 0, 0, 0])
        #expect(valuation.tokens[0].fraction24h == nil)
    }

    @Test(arguments: [Decimal(-1), Decimal(-2)])
    func `fraction at or below minus one gives no change`(fraction: Decimal) {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 1)

        let valued = Fixture.valued(token, market: Fixture.market(live: ["ethereum": 10], changes: ["ethereum": fraction]))

        #expect(valued.change24h == 0)
    }

    @Test func `aggregate percentage is the change over the prior total`() {
        let valuation = Fixture.valuation(
            [Fixture.input(Fixture.token(coinGeckoId: "ethereum", amount: 1))],
            market: Fixture.market(live: ["ethereum": 1100], changes: ["ethereum": tenth]))

        #expect(valuation.totals.change24h == 100)
        #expect(valuation.totals.changePercentage == tenth)
    }

    @Test(arguments: [
        (Decimal(100), Decimal(100), Decimal?.none),
        (Decimal(100), Decimal(50), nil),
        (Decimal(-50), Decimal(-100), nil),
        (Decimal(50), Decimal(150), Decimal(1) / 2)
    ])
    func `aggregate percentage is absent unless the prior total is positive`(
        change: Decimal,
        total: Decimal,
        percentage: Decimal?) {
        #expect(ValuationTotals.changePercentage(change: change, total: total) == percentage)
    }

    @Test func `aggregate change covers dust tokens`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.token("ETH", coinGeckoId: "ethereum", amount: 1)),
            Fixture.input(Fixture.token("DUST", coinGeckoId: "dust", amount: 1))
        ], market: Fixture.market(
            live: ["ethereum": 1100, "dust": Decimal(11) / 100],
            changes: ["ethereum": tenth, "dust": tenth]))

        #expect(valuation.totals.change24h == Decimal(10001) / 100)
    }

    @Test func `live price with only a historical fraction is estimated from the closes`() {
        let rows = [Fixture.closeRow("ethereum", 1000, day: -1), Fixture.closeRow("ethereum", 1100, day: 0)]
        let market = MarketPrices(
            liveUSD: ["ethereum": 1210],
            liveChanges24h: [:],
            closeRows: rows,
            isBackfillEnabled: true,
            now: Fixture.noon(0))

        let valued = Fixture.valued(Fixture.token(coinGeckoId: "ethereum", amount: 1), market: market)

        #expect(valued.source == .live)
        #expect(valued.change24h == 110)
    }
}

struct ValuationRowPricingTests {
    private typealias Fixture = ValuationFixtures

    @Test func `row price is value over amount across mixed sources`() {
        let live = Fixture.token("ETH", coinGeckoId: "ethereum", amount: 2)
        let sync = Fixture.token("ETH", coinGeckoId: nil, amount: 2, usdValue: 100)
        let valuation = Fixture.valuation(
            [Fixture.input(live), Fixture.input(sync)],
            market: Fixture.market(live: ["ethereum": 100], changes: ["ethereum": Decimal(1) / 20]))

        let pricing = RowPricing(tokens: valuation.tokens)

        #expect(pricing.price == 75)
        #expect(pricing.source == .live)
        #expect(pricing.fraction24h == Decimal(1) / 20)
    }

    @Test func `row without a valued counted token has no price`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.token("A", coinGeckoId: "a", amount: 1)),
            Fixture.input(Fixture.token("B", coinGeckoId: "b", role: .reward, amount: 1))
        ], market: Fixture.market(live: ["b": 10]))

        let pricing = RowPricing(tokens: valuation.tokens)

        #expect(pricing.price == nil)
        #expect(pricing.source == nil)
        #expect(pricing.fraction24h == nil)
    }

    @Test func `lead token ties break on source order then asset id`() throws {
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000A"))
        let highID = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000000B"))
        let manual = Fixture.token("M", assetId: highID, coinGeckoId: "m", amount: 1)
        let live = Fixture.token("L", assetId: lowID, coinGeckoId: "l", amount: 1)
        let otherLive = Fixture.token("K", assetId: highID, coinGeckoId: "k", amount: 1)
        let market = Fixture.market(live: ["l": 100, "k": 100], changes: ["l": 1, "k": 2])

        let bySource = Fixture.valuation(
            [Fixture.input(live), Fixture.input(manual)],
            market: market,
            overrides: [Fixture.manual(highID, price: 100)])
        let byAssetID = Fixture.valuation([Fixture.input(otherLive), Fixture.input(live)], market: market)

        #expect(RowPricing(tokens: bySource.tokens).source == .manual)
        #expect(RowPricing(tokens: byAssetID.tokens).fraction24h == 1)
    }

    @Test func `lead token ties on source and asset id break on the lowest price id`() {
        let assetId = UUID()
        let later = Fixture.token("X", assetId: assetId, coinGeckoId: "b-id", amount: 1)
        let earlier = Fixture.token("X", assetId: assetId, coinGeckoId: "a-id", amount: 1)
        let valuation = Fixture.valuation(
            [Fixture.input(later), Fixture.input(earlier)],
            market: Fixture.market(live: ["a-id": 100, "b-id": 100], changes: ["a-id": 1, "b-id": 2]))

        #expect(RowPricing(tokens: valuation.tokens).fraction24h == 1)
    }

    @Test func `largest valued counted token leads the row`() {
        let small = Fixture.token("S", coinGeckoId: "small", amount: 1)
        let large = Fixture.token("L", coinGeckoId: "large", role: .borrow, amount: 1)
        let reward = Fixture.token("R", coinGeckoId: "reward", role: .reward, amount: 1)
        let valuation = Fixture.valuation(
            [Fixture.input(small), Fixture.input(large), Fixture.input(reward)],
            market: Fixture.market(
                live: ["small": 10, "large": 50, "reward": 1000],
                changes: ["small": 1, "large": 2, "reward": 3]))

        let pricing = RowPricing(tokens: valuation.tokens)

        #expect(pricing.fraction24h == 2)
        #expect(pricing.price == 30)
    }

    @Test func `manual lead token gives the row no fraction`() {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 1)
        let valuation = Fixture.valuation(
            [Fixture.input(token)],
            market: Fixture.market(changes: ["ethereum": Decimal(1) / 10]),
            overrides: [Fixture.manual(token, price: 9)])

        let pricing = RowPricing(tokens: valuation.tokens)

        #expect(pricing.price == 9)
        #expect(pricing.source == .manual)
        #expect(pricing.fraction24h == nil)
    }
}

struct ValuationDisplayTests {
    private typealias Fixture = ValuationFixtures

    @Test func `every money field of every display result is scaled once and nothing else is`() throws {
        let rate = Fixture.decimal("2.5")
        let eth = Fixture.token("ETH", portfolioCategory: Fixture.eth, coinGeckoId: "ethereum", amount: 2, usdValue: 280)
        let loan = Fixture.synced("LOAN", 90, role: .borrow)
        let valuation = Fixture.valuation(
            [
                Fixture.input(Fixture.synced("USDC", 100, portfolioCategory: Fixture.stablecoins)),
                Fixture.input(eth),
                Fixture.input(Fixture.synced("MEME", 40, portfolioCategory: Fixture.meme)),
                Fixture.input(Fixture.synced("LEND", 500, role: .supply), positionType: .lending),
                Fixture.input(loan, positionType: .lending),
                Fixture.input(Fixture.synced("STK", 60, role: .stake), positionType: .staking),
                Fixture.input(Fixture.synced("FARM", 70, role: .lpToken), positionType: .farming),
                Fixture.input(Fixture.synced("VEST", 80), positionType: .vesting),
                Fixture.input(Fixture.synced("DUST", Fixture.decimal("0.6"))),
                Fixture.input(Fixture.synced("CRUMB", Fixture.decimal("0.3"), role: .borrow))
            ],
            market: Fixture.market(live: ["ethereum": 150], changes: ["ethereum": Fixture.decimal("0.5")]))

        let ethValued = valuation.tokens[1].display(rate: rate)
        let pricing = RowPricing(tokens: valuation.tokens[1 ... 1]).display(rate: rate)
        #expect(pricing.price == 375)
        #expect(pricing.fraction24h == Fixture.decimal("0.5"))
        #expect(ethValued.value == 750)
        #expect(ethValued.contribution == 750)
        #expect(ethValued.change24h == 250)
        #expect(ethValued.fraction24h == Fixture.decimal("0.5"))
        #expect(ethValued.token.amount == 2)
        #expect(ethValued.token.usdValue == 280)
        #expect(valuation.tokens[4].display(rate: rate).contribution == -225)

        let totals = valuation.totals.display(rate: rate)
        #expect(totals.gross == Fixture.decimal("2876.5"))
        #expect(totals.debt == Fixture.decimal("225.75"))
        #expect(totals.change24h == 250)
        #expect(totals.netAmount == 7)
        #expect(totals.syncTotal == Fixture.decimal("2600.75"))
        let percentage = try #require(totals.changePercentage)
        #expect(percentage == valuation.totals.changePercentage)

        let cards = valuation.summaryCards.display(rate: rate)
        #expect(cards.idle.stablecoinsAndFiat == 250)
        #expect(cards.idle.majors == 750)
        #expect(cards.idle.tokensAndMemecoins == Fixture.decimal("101.5"))
        #expect(cards.deployed.lending == 1250)
        #expect(cards.deployed.staked == 150)
        #expect(cards.deployed.yield == 175)
        #expect(cards.deployed.other == 200)
        #expect(cards.debt == Fixture.decimal("225.75"))

        let hidden = Fixture.list(valuation, .net) { $0.token.assetId }.hidden.display(rate: rate)
        #expect(hidden.rowCount == 2)
        #expect(hidden.unpricedCount == 0)
        #expect(hidden.gross == Fixture.decimal("1.5"))
        #expect(hidden.debt == Fixture.decimal("0.75"))
        #expect(hidden.net == Fixture.decimal("0.75"))
    }
}
