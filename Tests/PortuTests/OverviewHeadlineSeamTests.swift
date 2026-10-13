import Foundation
@testable import Portu
import PortuCore
import Testing

/// T2 for the headline (top bar and Sidebar header, one seam) and the summary cards, fed the shared
/// fixture. Expectations are worked out by hand from the spec.
struct OverviewHeadlineSeamTests {
    private typealias Fixture = OverviewValuationFixture

    // MARK: - Headline

    @Test func `headline total is the net of every valued token`() {
        let headline = OverviewFeature.headline(Fixture.context())

        #expect(headline.total == Fixture.decimal("10780.4"))
    }

    @Test func `headline 24h change is the exact change of every token with no dust filter`() {
        let headline = OverviewFeature.headline(Fixture.context())

        #expect(headline.change24h == Fixture.decimal("1522.1"))
        #expect(headline.changePercentage == Fixture.decimal("1522.1") / Fixture.decimal("9258.3"))
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
        #expect(headline.change24h == -300)
        #expect(headline.changePercentage == nil)
    }

    // MARK: - Summary cards

    @Test func `summary cards reconcile idle plus deployed minus debt with the headline`() {
        let cards = OverviewSummaryCardsFeature.cards(Fixture.context(), categories: PortfolioCategoryDefaults.categorySnapshots)
        let headline = OverviewFeature.headline(Fixture.context())

        #expect(cards.map(\.title) == ["Idle", "Deployed", "Debt"])
        #expect(total(of: "Idle", in: cards) + total(of: "Deployed", in: cards) - total(of: "Debt", in: cards) == headline.total)
        #expect(headline.total == Fixture.decimal("10780.4"))
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
        #expect(idle.rows.map(\.value) == [Fixture.decimal("1000.5"), 6000, Fixture.decimal("690.3")])
        #expect(deployed.rows.last == OverviewSummaryCardRow(label: "Other", value: 90))
        #expect(cards.first { $0.title == "Debt" }?.rows == [
            OverviewSummaryCardRow(label: "Borrowed", value: Fixture.decimal("1500.4"))
        ])
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
        #expect(headline.total == Fixture.decimal("9702.36"))
        #expect(headline.change24h == Fixture.decimal("1369.89"))
        #expect(idle.rows[0].value == Fixture.decimal("900.45"))
        #expect(total(of: "Debt", in: cards) == Fixture.decimal("1350.36"))
    }

    /// Core-module handoff: the module takes no rate, so only a seam can feed it a display-currency
    /// book. At 0.9 the token's USD ratio 105 / 10,000 = 0.0105 is inside the band, while a
    /// pre-scaled display ratio 94.5 / 10,000 = 0.00945 would fall outside it.
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
            prices: OverviewPriceInputs(livePricesUSD: [identity.historicalPriceID: 105]))

        #expect(OverviewFeature.headline(context).total == Fixture.decimal("94.5"))
    }

    private func total(of title: String, in cards: [OverviewSummaryCard]) -> Decimal {
        cards.first { $0.title == title }?.rows.reduce(Decimal.zero) { $0 + $1.value } ?? 0
    }
}

// MARK: - Ad-hoc portfolios (ported from the legacy total and change specs)

extension OverviewHeadlineSeamTests {
    @Test func `headline counts a sync only token at its sync value`() {
        let manualId = UUID()
        let context = Fixture.context(
            tokens: [
                token(symbol: "SYNC", amount: 1, usdValue: 10000),
                token(symbol: "LIVE", coinGeckoId: "live", amount: 2, usdValue: 2),
                token(symbol: "DEBT", coinGeckoId: "debt", role: .borrow, amount: 3, usdValue: 300),
                token(assetId: manualId, symbol: "MANUAL", amount: 4, usdValue: 0)
            ],
            overrides: [TokenPricingOverrideSnapshot(assetId: manualId, manualPriceUSD: 7)],
            livePricesUSD: ["live": 5, "debt": 2])

        #expect(OverviewFeature.headline(context).total == 10032)
    }

    @Test func `headline values an implausible onchain price at zero with no fallback`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xBadPrice")
        let context = Fixture.context(
            tokens: [token(symbol: "BAD", amount: 1_000_000, usdValue: 10, onchainIdentity: identity)],
            livePricesUSD: [identity.historicalPriceID: 1_000_000])

        #expect(OverviewFeature.headline(context).total == 0)
    }

    /// Newer-of (V1.5) with no live price: the sync value, unless a close is from a later UTC day.
    @Test func `headline takes the sync value unless a close is newer`() {
        let rate = Fixture.decimal("0.9")
        let close = HistoricalMarketPrices(closesUSD: ["bitcoin": HistoricalClose(day: Fixture.day(0), price: 61000)])
        let total = { (syncedAt: Date, historical: HistoricalMarketPrices) in
            OverviewFeature.headline(Fixture.context(
                tokens: [
                    token(symbol: "BTC", coinGeckoId: "bitcoin", amount: 1, usdValue: 60000, syncedAt: syncedAt),
                    token(symbol: "DEBT", coinGeckoId: "debt", role: .borrow, amount: 2, usdValue: 100, syncedAt: syncedAt)
                ],
                rate: rate,
                historical: historical)).total
        }

        #expect(total(Fixture.noon(0), .empty) == 53910)
        #expect(total(Fixture.noon(0), close) == 53910)
        #expect(total(Fixture.noon(-1), close) == 54810)
    }

    @Test func `headline converts a manual usd price once`() {
        let manualId = UUID()
        let context = Fixture.context(
            tokens: [
                token(symbol: "LIVE", coinGeckoId: "live", amount: 2, usdValue: 2),
                token(assetId: manualId, symbol: "MANUAL", amount: 4, usdValue: 0)
            ],
            overrides: [TokenPricingOverrideSnapshot(assetId: manualId, manualPriceUSD: 7)],
            rate: Fixture.decimal("0.9"),
            livePricesUSD: ["live": 5])

        #expect(OverviewFeature.headline(context).total == Fixture.decimal("34.2"))
    }

    /// A1 and A4: dust stays in the total and the change, whatever the threshold or the rate.
    @Test(arguments: [Decimal(0), 1, 100])
    func `headline counts dust whatever the threshold`(threshold: Decimal) {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xToken")
        let context = Fixture.context(
            tokens: [token(symbol: "LIVE", amount: 1, usdValue: 0, onchainIdentity: identity)],
            settings: TokenDashboardSettings(minimumDashboardValue: threshold, hideUnpriced: true, hideDust: true),
            rate: Fixture.decimal("0.5"),
            livePricesUSD: [identity.historicalPriceID: Fixture.decimal("0.6")],
            liveChanges24h: [identity.historicalPriceID: Fixture.decimal("0.5")])

        let headline = OverviewFeature.headline(context)

        #expect(headline.total == Fixture.decimal("0.3"))
        #expect(headline.change24h == Fixture.decimal("0.1"))
    }

    /// The exact formula (V4): 20 × 0.25 / 1.25 = 4 for the mapped token, 15 × −0.2 / 0.8 = −3.75,
    /// and −16 × 0.25 / 1.25 = −3.2 for the debt. MAP sits on a chain with no CoinGecko platform, so
    /// its mapping applies (I3) and its onchain id's price is not a fallback.
    @Test func `headline change prices a mapped token by its mapping and the rest by onchain id`() {
        let mappedIdentity = OnchainTokenIdentity(chain: .degen, contractAddress: "0xMapped")
        let onchainIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xProvider")
        let borrowIdentity = OnchainTokenIdentity(chain: .arbitrum, contractAddress: "0xBorrow")
        let context = Fixture.context(
            tokens: [
                token(symbol: "MAP", amount: 2, usdValue: 20, onchainIdentity: mappedIdentity),
                token(symbol: "ZAP", amount: 3, usdValue: 15, onchainIdentity: onchainIdentity),
                token(symbol: "DEBT", role: .borrow, amount: 4, usdValue: 16, onchainIdentity: borrowIdentity)
            ],
            mappings: [TokenIdentityMappingSnapshot(identity: mappedIdentity, coinGeckoId: "mapped-token")],
            livePricesUSD: [
                "mapped-token": 10,
                mappedIdentity.historicalPriceID: 1000,
                onchainIdentity.historicalPriceID: 5,
                borrowIdentity.historicalPriceID: 4
            ],
            liveChanges24h: [
                "mapped-token": Fixture.decimal("0.25"),
                mappedIdentity.historicalPriceID: 9,
                onchainIdentity.historicalPriceID: Fixture.decimal("-0.2"),
                borrowIdentity.historicalPriceID: Fixture.decimal("0.25")
            ])

        let headline = OverviewFeature.headline(context)

        #expect(headline.total == 19)
        #expect(headline.change24h == Fixture.decimal("-2.95"))
    }

    /// A4: the dust token's change counts. Exact formula: 0.25 × 1 / 2 + 10 × 0.25 / 1.25.
    @Test func `headline change counts a dust outlier`() {
        let dustIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xDust")
        let visibleIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xVisible")
        let context = Fixture.context(
            tokens: [
                token(symbol: "DUST", amount: 1, usdValue: Fixture.decimal("0.25"), onchainIdentity: dustIdentity),
                token(symbol: "VISIBLE", amount: 2, usdValue: 10, onchainIdentity: visibleIdentity)
            ],
            liveChanges24h: [dustIdentity.historicalPriceID: 1, visibleIdentity.historicalPriceID: Fixture.decimal("0.25")])

        #expect(OverviewFeature.headline(context).change24h == Fixture.decimal("2.125"))
    }

    /// V4 bounds an absurd fraction: the dust token adds at most its 0.25 contribution, so a
    /// 1e9 change cannot blow up the headline. VISIBLE adds 10 × 0.25 / 1.25 = 2.
    @Test func `headline change keeps a dust outlier fraction bounded by its contribution`() {
        let dustIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xDust")
        let visibleIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xVisible")
        let context = Fixture.context(
            tokens: [
                token(symbol: "DUST", amount: 1, usdValue: Fixture.decimal("0.25"), onchainIdentity: dustIdentity),
                token(symbol: "VISIBLE", amount: 2, usdValue: 10, onchainIdentity: visibleIdentity)
            ],
            liveChanges24h: [
                dustIdentity.historicalPriceID: 1_000_000_000,
                visibleIdentity.historicalPriceID: Fixture.decimal("0.25")
            ])

        let change = OverviewFeature.headline(context).change24h
        #expect(change < Fixture.decimal("2.25"))
        #expect(change > Fixture.decimal("2.2499"))
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil,
        syncedAt: Date = Fixture.noon(0)) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: .major,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue,
            syncedAt: syncedAt)
    }
}
