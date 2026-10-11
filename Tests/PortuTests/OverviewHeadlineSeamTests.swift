import Foundation
@testable import Portu
import PortuCore
import Testing

/// T2 for the headline (top bar and Sidebar header, one seam) and the summary cards, fed the shared
/// fixture. Expectations are worked out by hand from the spec; a block that today's pricing still
/// misses is a known issue until step 5 moves the seams to `PortfolioValuation`.
struct OverviewHeadlineSeamTests {
    private typealias Fixture = OverviewValuationFixture

    // MARK: - Headline

    @Test func `headline total is the net of every valued token`() {
        let headline = OverviewFeature.headline(Fixture.context())

        withKnownIssue("converges in step 5: A1 — the total includes dust, dust borrows, sync-only tokens and same-day sync values") {
            #expect(headline.total == Fixture.decimal("10780.4"))
        }
    }

    @Test func `headline 24h change is the exact change of every token with no dust filter`() {
        let headline = OverviewFeature.headline(Fixture.context())

        withKnownIssue("converges in step 5: A4 and V4 — exact formula, and the 24h change no longer drops dust") {
            #expect(headline.change24h == Fixture.decimal("1522.1"))
            #expect(headline.changePercentage == Fixture.decimal("1522.1") / Fixture.decimal("9258.3"))
        }
    }

    @Test func `headline percentage is the change over the prior total`() {
        let headline = OverviewFeature.headline(Fixture.context())

        #expect(headline.change24h > 0)
        #expect(headline.total - headline.change24h > 0)
        #expect(headline.changePercentage == headline.change24h / (headline.total - headline.change24h))
    }

    @Test func `headline total and change scale linearly with the display rate`() {
        let rate = Fixture.decimal("0.9")
        let usd = OverviewFeature.headline(Fixture.context())
        let display = OverviewFeature.headline(Fixture.context(rate: rate))

        #expect(display.total == usd.total * rate)
        #expect(display.change24h == usd.change24h * rate)
    }

    @Test func `headline percentage is a dash when the prior total is not positive`() {
        let borrowOnly = Fixture.inputs.filter { $0.tokenId == Fixture.tokenID(13) }
        let headline = OverviewFeature.headline(Fixture.context(inputs: borrowOnly))

        #expect(headline.total == -1500)
        withKnownIssue("converges in step 5: A4 — no percentage unless the prior total is positive") {
            #expect(headline.change24h == -300)
            #expect(headline.changePercentage == nil)
        }
    }

    // MARK: - Summary cards

    @Test func `summary cards reconcile idle plus deployed minus debt with the headline`() {
        let cards = OverviewSummaryCardsFeature.cards(Fixture.context(), categories: PortfolioCategoryDefaults.categorySnapshots)
        let headline = OverviewFeature.headline(Fixture.context())

        withKnownIssue("converges in step 5: A3 — a Debt card and an Other row, so Idle + Deployed − Debt = net total") {
            #expect(cards.map(\.title) == ["Idle", "Deployed", "Debt"])
            #expect(total(of: "Idle", in: cards) + total(of: "Deployed", in: cards) - total(of: "Debt", in: cards) == headline.total)
            #expect(headline.total == Fixture.decimal("10780.4"))
        }
    }

    @Test func `summary card rows hold the module values`() throws {
        let cards = OverviewSummaryCardsFeature.cards(Fixture.context(), categories: PortfolioCategoryDefaults.categorySnapshots)
        let idle = try #require(cards.first { $0.title == "Idle" })
        let deployed = try #require(cards.first { $0.title == "Deployed" })

        #expect(idle.rows.map(\.label) == ["Stablecoins & Fiat", "BTC / ETH / SOL", "Tokens & Memecoins"])
        #expect(idle.rows[1].value == 6000)
        #expect(Array(deployed.rows.prefix(3)) == [
            OverviewSummaryCardRow(label: "Lending", value: 3000),
            OverviewSummaryCardRow(label: "Staked", value: 1500),
            OverviewSummaryCardRow(label: "Yield", value: 0)
        ])
        withKnownIssue("converges in step 5: A3/S2 — rows include dust, sync-only and mapped tokens, vesting lands in Other, borrows in Debt") {
            #expect(idle.rows.map(\.value) == [Fixture.decimal("1000.5"), 6000, Fixture.decimal("690.3")])
            #expect(deployed.rows.last == OverviewSummaryCardRow(label: "Other", value: 90))
            #expect(cards.first { $0.title == "Debt" }?.rows == [
                OverviewSummaryCardRow(label: "Borrowed", value: Fixture.decimal("1500.4"))
            ])
        }
    }

    // MARK: - Display currency

    @Test func `display rate is applied once to the headline and the cards`() throws {
        let rate = Fixture.decimal("0.9")
        let headline = OverviewFeature.headline(Fixture.context(rate: rate))
        let cards = OverviewSummaryCardsFeature.cards(
            Fixture.context(rate: rate),
            categories: PortfolioCategoryDefaults.categorySnapshots)
        let idle = try #require(cards.first { $0.title == "Idle" })
        let deployed = try #require(cards.first { $0.title == "Deployed" })

        #expect(idle.rows[1].value == 5400)
        #expect(deployed.rows[0].value == 2700)
        #expect(deployed.rows[1].value == 1350)
        withKnownIssue("converges in step 5: A1/A3 at a non-USD rate — dust, sync-only and same-day sync values count") {
            #expect(headline.total == Fixture.decimal("9702.36"))
            #expect(headline.change24h == Fixture.decimal("1369.89"))
            #expect(idle.rows[0].value == Fixture.decimal("900.45"))
            #expect(total(of: "Debt", in: cards) == Fixture.decimal("1350.36"))
        }
    }

    /// Core-module handoff: the module takes no rate, so only a seam can feed it a display-currency
    /// book. At 0.9 the token's USD ratio 105 / 10,000 = 0.0105 is inside the band, while today's
    /// display ratio 94.5 / 10,000 = 0.00945 falls outside it.
    @Test func `onchain plausibility compares usd with usd at a non usd rate`() {
        let identity = OnchainTokenIdentity(chain: .ethereum, contractAddress: "0xc0de00000000000000000000000000000000c0de")
        let input = ValuationInput(
            tokenId: UUID(),
            token: TokenEntry(
                assetId: UUID(),
                symbol: "EDGE",
                name: "Edge Token",
                category: .other,
                coinGeckoId: nil,
                onchainIdentity: identity,
                role: .balance,
                amount: 1,
                usdValue: 10000,
                syncedAt: Fixture.noon(0)),
            position: PositionContext(positionId: UUID(), positionType: .idle, chain: .ethereum))
        let rate = Fixture.decimal("0.9")
        let context = OverviewValuationContext(
            inputs: [input],
            overrides: [],
            mappings: [],
            settings: .defaults,
            usdToDisplayRate: rate,
            prices: OverviewPriceInputs(
                livePricesUSD: [identity.historicalPriceID: 105],
                liveDisplayPrices: [identity.historicalPriceID: Fixture.decimal("94.5")]))

        withKnownIssue("converges in step 5: V3 — plausibility reads livePricesUSD, never the display book") {
            #expect(OverviewFeature.headline(context).total == Fixture.decimal("94.5"))
        }
    }

    private func total(of title: String, in cards: [OverviewSummaryCard]) -> Decimal {
        cards.first { $0.title == title }?.rows.reduce(Decimal.zero) { $0 + $1.value } ?? 0
    }
}
