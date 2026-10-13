import Foundation
import PortuCore
import Testing

struct ValuationCappedListTests {
    private typealias Fixture = ValuationFixtures

    @Test func `donut top five plus other plus hidden share is one hundred percent`() throws {
        let values: [Decimal] = [30, 25, 20, 10, 8, 4, 2, Fixture.decimal("0.5")]
        let valuation = Fixture.valuation(values.enumerated().map { index, value in
            Fixture.input(Fixture.synced("T\(index)", value))
        })

        let donut = Fixture.list(valuation, .gross) { $0.token.symbol }
            .ranked(top: 5)
        let shares = try #require(donut.shares())

        #expect(donut.rows.map(\.key) == ["T0", "T1", "T2", "T3", "T4"])
        #expect(try #require(donut.remainder).gross == 6)
        #expect(donut.hidden.gross == Fixture.decimal("0.5"))
        #expect(donut.total == valuation.totals.gross)
        #expect(shares.rows.count == 5)
        #expect(shares.remainder == Fixture.decimal("0.06"))
        #expect(shares.hidden == Fixture.decimal("0.005"))
        #expect(shares.all.reduce(0, +) == 1)
    }

    /// Whole percents for the donut legend: the hidden 0.5 of 99.5 rounds up to 1%.
    @Test func `shares round to the step the caller asks for`() throws {
        let values: [Decimal] = [30, 25, 20, 10, 8, 4, 2, Fixture.decimal("0.5")]
        let valuation = Fixture.valuation(values.enumerated().map { index, value in
            Fixture.input(Fixture.synced("T\(index)", value))
        })

        let donut = Fixture.list(valuation, .gross) { $0.token.symbol }.ranked(top: 5)
        let shares = try #require(donut.shares(fractionDigits: 2))

        #expect(shares.rows == ["0.3", "0.25", "0.2", "0.1", "0.08"].map(Fixture.decimal))
        #expect(shares.remainder == Fixture.decimal("0.06"))
        #expect(shares.hidden == Fixture.decimal("0.01"))
        #expect(shares.all.reduce(0, +) == 1)
        #expect(donut.shares() == donut.shares(fractionDigits: 3))
    }

    @Test func `ranking ties use the caller's tie break`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("B", 10)),
            Fixture.input(Fixture.synced("A", 10)),
            Fixture.input(Fixture.synced("C", 20))
        ])
        let list = Fixture.list(valuation, .gross) { $0.token.symbol }

        #expect(list.ranked(tieBreak: { $0.key < $1.key }).rows.map(\.key) == ["C", "A", "B"])
        #expect(list.ranked().rows.map(\.key) == ["C", "B", "A"])
    }

    @Test func `no remainder when everything fits`() throws {
        let valuation = Fixture.valuation([Fixture.input(Fixture.synced("A", 10))])

        let ranked = Fixture.list(valuation, .gross) { $0.token.symbol }.ranked(top: 5)
        let shares = try #require(ranked.shares())

        #expect(ranked.remainder == nil)
        #expect(ranked.displayRemainder(rate: 2) == nil)
        #expect(shares.remainder == nil)
        #expect(shares.hidden == nil)
        #expect(shares.rows == [1])
    }

    @Test func `list totals and the remainder convert to the display currency`() {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("A", 30)),
            Fixture.input(Fixture.synced("B", 20)),
            Fixture.input(Fixture.synced("C", 10))
        ])
        let list = Fixture.list(valuation, .gross) { $0.token.symbol }

        let ranked = list.ranked(top: 1)

        #expect(list.displayTotal(rate: Fixture.decimal("0.5")) == 30)
        #expect(ranked.displayTotal(rate: Fixture.decimal("0.5")) == 30)
        #expect(ranked.displayRemainder(rate: Fixture.decimal("0.5")) == 15)
        #expect(ranked.total == 60)
    }

    @Test func `visible plus remainder plus hidden equals the total on every basis`() {
        let hedged = UUID()
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("A", 100)),
            Fixture.input(Fixture.synced("B", 50)),
            Fixture.input(Fixture.synced("C", 40, assetId: hedged, role: .supply)),
            Fixture.input(Fixture.synced("C", 90, assetId: hedged, role: .borrow)),
            Fixture.input(Fixture.synced("D", 30, role: .borrow)),
            Fixture.input(Fixture.synced("E", Fixture.decimal("0.4"))),
            Fixture.input(Fixture.synced("F", Fixture.decimal("0.3"), role: .borrow))
        ])

        for basis in [DashboardBasis.gross, .net, .debt] {
            let ranked = Fixture.list(valuation, basis) { $0.token.symbol }
                .ranked(top: 1)
            let shown = ranked.rows.reduce(ValuationTotals.zero) { $0 + $1.totals }
            let remainder = ranked.remainder ?? .zero
            #expect(shown.value(on: basis) + remainder.value(on: basis) + ranked.hidden.value(on: basis) == ranked.total)
        }

        let exposure = Fixture.list(valuation, .net) { $0.token.symbol }.ranked(top: 2)
        let shown = exposure.rows.reduce(ValuationTotals.zero) { $0 + $1.totals } + (exposure.remainder ?? .zero)
        #expect(shown.gross + exposure.hidden.gross == valuation.totals.gross)
        #expect(shown.debt + exposure.hidden.debt == valuation.totals.debt)
        #expect(shown.net + exposure.hidden.net == valuation.totals.net)
    }

    @Test func `key changes keep visible positive tokens ranked by absolute change and capped`() throws {
        var inputs: [ValuationInput] = []
        var live: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]
        for index in 0 ..< 25 {
            let id = "t\(index)"
            inputs.append(Fixture.input(Fixture.token("T\(index)", coinGeckoId: id, amount: 1)))
            live[id] = 100
            changes[id] = Decimal(index + 1) / 100
        }
        inputs.append(Fixture.input(Fixture.token("DUST", coinGeckoId: "dust", amount: 1)))
        inputs.append(Fixture.input(Fixture.token("LOAN", coinGeckoId: "loan", role: .borrow, amount: 1)))
        inputs.append(Fixture.input(Fixture.token("REW", coinGeckoId: "rew", role: .reward, amount: 1)))
        inputs.append(Fixture.input(Fixture.token("FLAT", coinGeckoId: "flat", amount: 1)))
        live["dust"] = Fixture.decimal("0.5")
        live["loan"] = 100
        live["rew"] = 100
        live["flat"] = 100
        changes["dust"] = 9
        changes["loan"] = -9
        changes["rew"] = 9
        let valuation = Fixture.valuation(inputs, market: Fixture.market(live: live, changes: changes))

        let movers = valuation.keyChanges(settings: .defaults)

        #expect(movers.count == 20)
        #expect(try #require(movers.first).token.symbol == "T24")
        #expect(try #require(movers.last).token.symbol == "T5")
        #expect(!movers.contains { ["DUST", "LOAN", "REW", "FLAT"].contains($0.token.symbol) })
    }

    @Test func `key changes leave out borrows and hidden dust even when they move the most`() {
        let shownDust = Fixture.token("SHOWN", coinGeckoId: "shown", amount: 1)
        let valuation = Fixture.valuation(
            [
                Fixture.input(Fixture.token("V1", coinGeckoId: "v1", amount: 1)),
                Fixture.input(Fixture.token("V2", coinGeckoId: "v2", amount: 1)),
                Fixture.input(Fixture.token("LOAN", coinGeckoId: "loan", role: .borrow, amount: 1)),
                Fixture.input(Fixture.token("DUST", coinGeckoId: "dust", amount: 1)),
                Fixture.input(shownDust)
            ],
            market: Fixture.market(
                live: ["v1": 100, "v2": 100, "loan": 100, "dust": Fixture.decimal("0.5"), "shown": Fixture.decimal("0.5")],
                changes: [
                    "v1": Fixture.decimal("0.001"),
                    "v2": Fixture.decimal("0.002"),
                    "loan": Fixture.decimal("0.5"),
                    "dust": 9,
                    "shown": 4
                ]),
            overrides: [Fixture.alwaysShow(shownDust)])

        let movers = valuation.keyChanges(settings: .defaults)

        #expect(movers.map(\.token.symbol) == ["SHOWN", "V2", "V1"])
    }

    /// Twenty gainers at +10 each and one loser at −500: by signed change the loser would come 21st
    /// and miss the cap.
    @Test func `key changes rank a large loser ahead of smaller gainers`() throws {
        var inputs: [ValuationInput] = []
        var live: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]
        for index in 0 ..< 20 {
            let id = "g\(index)"
            inputs.append(Fixture.input(Fixture.token("G\(index)", coinGeckoId: id, amount: 1)))
            live[id] = 110
            changes[id] = Fixture.decimal("0.1")
        }
        inputs.append(Fixture.input(Fixture.token("LOSER", coinGeckoId: "loser", amount: 1)))
        live["loser"] = 500
        changes["loser"] = Fixture.decimal("-0.5")
        let valuation = Fixture.valuation(inputs, market: Fixture.market(live: live, changes: changes))

        let movers = valuation.keyChanges(settings: .defaults, limit: 20)

        #expect(movers.count == 20)
        #expect(try #require(movers.first).token.symbol == "LOSER")
        #expect(try #require(movers.first).change24h == -500)
        #expect(movers.dropFirst().allSatisfy { $0.change24h == 10 })
    }

    @Test func `key change ties are broken by symbol`() {
        let valuation = Fixture.valuation(
            [
                Fixture.input(Fixture.token("B", coinGeckoId: "b", amount: 1)),
                Fixture.input(Fixture.token("A", coinGeckoId: "a", amount: 1)),
                Fixture.input(Fixture.token("C", coinGeckoId: "c", amount: 1))
            ],
            market: Fixture.market(
                live: ["a": 110, "b": 110, "c": 90],
                changes: ["a": Fixture.decimal("0.1"), "b": Fixture.decimal("0.1"), "c": Fixture.decimal("-0.1")]))

        let movers = valuation.keyChanges(settings: .defaults, limit: 2)

        #expect(movers.map(\.token.symbol) == ["A", "B"])
    }

    @Test func `health weights over more than five assets sum to one hundred percent`() throws {
        let values: [Decimal] = [3, 3, 3, 1, 1, 1, 1]
        let valuation = Fixture.valuation(values.enumerated().map { index, value in
            Fixture.input(Fixture.synced("S\(index)", value))
        })

        let health = Fixture.list(valuation, .positiveNet) { $0.token.symbol }
            .ranked()
        let shares = try #require(health.shares())

        #expect(health.rows.count == 7)
        #expect(shares.all.reduce(0, +) == 1)
        #expect(shares.rows.first == Fixture.decimal("0.23"))
    }
}

struct ValuationShareTests {
    private typealias Fixture = ValuationFixtures

    @Test func `rounded shares including a hidden share sum to one hundred percent`() throws {
        let shares = try #require(ListShares.rounded([1, 1, 1]))

        #expect(shares == [Fixture.decimal("0.334"), Fixture.decimal("0.333"), Fixture.decimal("0.333")])
    }

    @Test func `rounding error ties go to the larger absolute value`() throws {
        let shares = try #require(ListShares.rounded([1, 1, 2]))

        #expect(shares == [Fixture.decimal("0.25"), Fixture.decimal("0.25"), Fixture.decimal("0.5")])
        let thirds = try #require(ListShares.rounded([1, 1, 4]))
        #expect(thirds == [Fixture.decimal("0.167"), Fixture.decimal("0.167"), Fixture.decimal("0.666")])
    }

    @Test func `rounding error ties go to the larger absolute value when it is negative`() throws {
        let shares = try #require(ListShares.rounded([-4, 2, 2, 3]))

        #expect(shares == [Fixture.decimal("-1.334"), Fixture.decimal("0.667"), Fixture.decimal("0.667"), 1])
    }

    @Test func `rounding error and value ties go to the earlier row`() throws {
        let shares = try #require(ListShares.rounded([1, 2, 2, 1, 1]))

        #expect(shares == [0.143, 0.285, 0.286, 0.143, 0.143].map { Fixture.decimal("\($0)") })
    }

    /// Largest remainder: the large row keeps its own rounded share instead of absorbing the
    /// residual of every tiny row.
    @Test func `one large row among many tiny rows shows its own rounded share`() throws {
        let values = [Decimal(9520)] + Array(repeating: Decimal(4), count: 120)

        let shares = try #require(ListShares.rounded(values))

        #expect(shares.first == Fixture.decimal("0.952"))
        #expect(shares.dropFirst().prefix(48).allSatisfy { $0 == Fixture.decimal("0.001") })
        #expect(shares.dropFirst(49).allSatisfy { $0 == 0 })
        #expect(shares.reduce(0, +) == 1)
        #expect(Self.largestError(values, shares) < Fixture.decimal("0.001"))
    }

    @Test func `a negative row with the largest rounding error takes the step`() throws {
        let up = try #require(ListShares.rounded([150, Fixture.decimal("-50.06"), Fixture.decimal("0.03"), Fixture.decimal("0.03")]))
        let down = try #require(ListShares.rounded([150, Fixture.decimal("-49.94"), Fixture.decimal("-0.03"), Fixture.decimal("-0.03")]))

        #expect(up == [Fixture.decimal("1.5"), Fixture.decimal("-0.5"), 0, 0])
        #expect(down == [Fixture.decimal("1.5"), Fixture.decimal("-0.5"), 0, 0])
    }

    @Test func `whole percent shares round by largest remainder`() throws {
        let shares = try #require(ListShares.rounded([98200, 450, 450, 450, 450], fractionDigits: 2))

        #expect(shares == [Fixture.decimal("0.98"), Fixture.decimal("0.01"), Fixture.decimal("0.01"), 0, 0])
    }

    @Test func `random lists round within one step of exact and sum to one hundred percent`() {
        var generator = SplitMix64(seed: 122)
        for _ in 0 ..< 200 {
            let count = Int.random(in: 1 ... 60, using: &generator)
            var values = (0 ..< count).map { _ in
                Decimal(Int.random(in: -500 ... 100_000, using: &generator)) / 100
            }
            if values.reduce(Decimal.zero, +) <= 0 {
                values.append(1000)
            }
            guard let shares = ListShares.rounded(values) else {
                Issue.record("no shares for \(values)")
                continue
            }

            #expect(shares.reduce(0, +) == 1, "\(values)")
            #expect(Self.largestError(values, shares) < Fixture.decimal("0.001"), "\(values)")
        }
    }

    private static func largestError(_ values: [Decimal], _ shares: [Decimal]) -> Decimal {
        let total = values.reduce(Decimal.zero, +)
        return zip(values, shares).map { abs($1 - $0 / total) }.max() ?? 0
    }

    @Test func `hidden balances take part in the shares`() throws {
        let valuation = Fixture.valuation([
            Fixture.input(Fixture.synced("A", 1)),
            Fixture.input(Fixture.synced("B", 1)),
            Fixture.input(Fixture.synced("C", Fixture.decimal("0.5"))),
            Fixture.input(Fixture.synced("D", Fixture.decimal("0.5")))
        ])

        let ranked = Fixture.list(valuation, .net) { $0.token.symbol }.ranked()
        let shares = try #require(ranked.shares())

        #expect(shares.rows == [Fixture.decimal("0.334"), Fixture.decimal("0.333")])
        #expect(shares.hidden == Fixture.decimal("0.333"))
    }

    @Test(arguments: [[Decimal](), [0, 0], [Decimal(-5), 2]])
    func `empty zero and negative totals give no shares`(values: [Decimal]) {
        #expect(ListShares.rounded(values) == nil)
    }

    @Test func `negative row on a net list has a negative share`() {
        #expect(ListShares.rounded([150, -50]) == [Fixture.decimal("1.5"), Fixture.decimal("-0.5")])
    }
}
