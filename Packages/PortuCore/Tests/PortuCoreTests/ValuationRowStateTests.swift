import Foundation
import PortuCore
import Testing

struct ValuationRowStateTests {
    private typealias Fixture = ValuationFixtures

    @Test func `row state precedence is ignored, then not counted, then unpriced, then counted`() {
        let ignoredReward = Fixture.token("IGN", coinGeckoId: "ign", role: .reward, amount: 0)
        let unpricedReward = Fixture.token("REW", coinGeckoId: "rew", role: .reward, amount: 1)
        let unpriced = Fixture.token("NOP", coinGeckoId: "nop", amount: 1)
        let priced = Fixture.token("ETH", coinGeckoId: "ethereum", amount: 1)
        let valuation = Fixture.valuation(
            [ignoredReward, unpricedReward, unpriced, priced].map { Fixture.input($0) },
            market: Fixture.market(live: ["ethereum": 3000]),
            overrides: [Fixture.ignore(ignoredReward)])

        #expect(valuation.tokens.map(\.source) == [.ignored, .unpriced, .unpriced, .live])
        #expect(valuation.tokens.map(\.rowState) == [.ignored, .notCounted, .unpriced, .counted])
    }

    @Test func `reward with a live price is not counted and keeps its value`() throws {
        let reward = Fixture.token("SOL", coinGeckoId: "solana", role: .reward, amount: 2, usdValue: 280)
        let valuation = Fixture.valuation([Fixture.input(reward)], market: Fixture.market(live: ["solana": 150]))

        let token = try #require(valuation.tokens.first)
        #expect(token.source == .live)
        #expect(token.value == 300)
        #expect(token.contribution == 0)
        #expect(token.rowState == .notCounted)
    }

    @Test(arguments: [Decimal(0), Decimal(-1)])
    func `zero and negative amounts are not counted`(amount: Decimal) throws {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: amount, usdValue: 100)
        let valuation = Fixture.valuation([Fixture.input(token)], market: Fixture.market(live: ["ethereum": 3000]))

        let valued = try #require(valuation.tokens.first)
        #expect(valued.value == 0)
        #expect(valued.rowState == .notCounted)
    }

    @Test func `ignored token that would be unpriced is ignored`() throws {
        let token = Fixture.token("SCAM", coinGeckoId: "scam", amount: 1000)
        let valuation = Fixture.valuation([Fixture.input(token)], overrides: [Fixture.ignore(token)])

        let valued = try #require(valuation.tokens.first)
        #expect(valued.value == 0)
        #expect(valued.rowState == .ignored)
    }

    @Test func `ignored reward is ignored`() throws {
        let reward = Fixture.token("SOL", coinGeckoId: "solana", role: .reward, amount: 1, usdValue: 150)
        let valuation = Fixture.valuation(
            [Fixture.input(reward)],
            market: Fixture.market(live: ["solana": 150]),
            overrides: [Fixture.ignore(reward)])

        let valued = try #require(valuation.tokens.first)
        #expect(valued.value == 0)
        #expect(valued.rowState == .ignored)
    }

    @Test func `counted borrow shows a negative contribution`() throws {
        let borrow = Fixture.token(coinGeckoId: "ethereum", role: .borrow, amount: Fixture.decimal("0.5"), usdValue: 1450)
        let valuation = Fixture.valuation([Fixture.input(borrow)], market: Fixture.market(live: ["ethereum": 3000]))

        let valued = try #require(valuation.tokens.first)
        #expect(valued.value == 1500)
        #expect(valued.contribution == -1500)
        #expect(valued.rowState == .counted)
    }

    @Test func `implausible onchain live price leaves the row unpriced`() throws {
        let identity = Fixture.onchain()
        let token = Fixture.token("BAD", onchainIdentity: identity, amount: 100, usdValue: 5000)
        let valuation = Fixture.valuation(
            [Fixture.input(token)],
            market: Fixture.market(live: [identity.historicalPriceID: 10000]))

        let valued = try #require(valuation.tokens.first)
        #expect(valued.source == .unpriced)
        #expect(valued.rowState == .unpriced)
    }

    @Test func `row value is the contribution when counted, the value when not counted, else nil`() {
        let borrow = Fixture.token("ETH", coinGeckoId: "ethereum", role: .borrow, amount: 1)
        let reward = Fixture.token("SOL", coinGeckoId: "solana", role: .reward, amount: 2)
        let unpriced = Fixture.token("NOP", coinGeckoId: "nop", amount: 1)
        let ignored = Fixture.token("SCAM", coinGeckoId: "scam", amount: 1000, usdValue: 500)
        let valuation = Fixture.valuation(
            [borrow, reward, unpriced, ignored].map { Fixture.input($0) },
            market: Fixture.market(live: ["ethereum": 3000, "solana": 150]),
            overrides: [Fixture.ignore(ignored)])
        let shown = valuation.tokens.map { $0.display(rate: 2) }

        #expect(valuation.tokens.map(\.rowState) == [.counted, .notCounted, .unpriced, .ignored])
        #expect(valuation.tokens.map(\.rowValue) == [-3000, 300, nil, nil])
        #expect(shown.map(\.rowValue) == [-6000, 600, nil, nil])
    }

    @Test func `a not-counted zero amount has a row value of zero, not none`() throws {
        let token = Fixture.token(coinGeckoId: "ethereum", amount: 0, usdValue: 100)
        let valuation = Fixture.valuation([Fixture.input(token)], market: Fixture.market(live: ["ethereum": 3000]))

        let valued = try #require(valuation.tokens.first)
        #expect(valued.rowState == .notCounted)
        #expect(valued.rowValue == 0)
    }

    @Test func `show all keeps dust and unpriced rows visible with no hidden line`() {
        let dust = Fixture.synced("DUST", Fixture.decimal("0.5"))
        let unpriced = Fixture.token("NOP", coinGeckoId: "nop", amount: 1)
        let priced = Fixture.synced("ETH", 3000)
        let ignored = Fixture.synced("SCAM", 500)
        let reward = Fixture.token("REW", coinGeckoId: "rew", role: .reward, amount: 1, usdValue: 5)
        let valuation = Fixture.valuation(
            [dust, unpriced, priced, ignored, reward].map { Fixture.input($0) },
            overrides: [Fixture.ignore(ignored)])

        let list = Fixture.list(valuation, .net, settings: .showAll) { $0.token.assetId }

        #expect(TokenDashboardSettings.showAll.minimumDashboardValue == TokenDashboardSettings.defaultMinimumDashboardValue)
        #expect(list.rows.map(\.status) == [.dust, .unpriced, .priced, .ignored, .notCounted])
        #expect(list.rows.filter { !$0.status.isDashboardRow }.allSatisfy { !$0.isVisible })
        #expect(Set(list.visibleRows.map(\.key)) == [dust.assetId, unpriced.assetId, priced.assetId])
        #expect(list.hidden.isEmpty)
    }
}
