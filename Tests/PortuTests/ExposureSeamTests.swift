import Foundation
@testable import Portu
import PortuCore
import Testing

/// The Exposure seam (S4, A7, F1–F3, T2) over the shared fixture and variants of it. Every value is
/// worked out by hand in USD from the fixture tables.
///
/// The shared fixture's asset table hides DAI (0.5 dust), BAD (unpriced) and the USDT borrow (0.4
/// dust); its category table hides nothing, since DAI and USDT share the Stablecoins row with USDC.
struct ExposureSeamTests {
    private typealias Fixture = PortfolioValuationFixture

    // MARK: - Summary

    /// A1, A2, A7 and S4: Spot − Liabilities is the headline. Number changes → Exposure: "Spot
    /// total and Liabilities include dust and sync-valued tokens" and "Net exposure (excl.
    /// stablecoins) includes dust, sync-only tokens and dust borrows".
    @Test func `the summary is the portfolio totals and the net total is the overview headline`() {
        let context = Fixture.context()
        let summary = ExposureFeature.dashboard(context).summary

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(summary.totalSpot == Fixture.decimal("12280.8"))
            #expect(summary.totalLiabilities == Fixture.decimal("1500.4"))
            #expect(summary.netTotal == Fixture.decimal("10780.4"))
            #expect(summary.netTotal == OverviewFeature.headline(context).total)
            // USDC, DAI and the USDT borrow are stablecoins.
            #expect(summary.netExposure == Fixture.decimal("9780.3"))
            #expect(summary.netExposureShare == Fixture.decimal("9780.3") / Fixture.decimal("12280.8"))
        }
    }

    /// Mostly stablecoins, with a stablecoin borrow: they count in Spot, Liabilities and the Net
    /// total, never in Net exposure. Three stablecoin assets fold into one category row.
    @Test func `a stablecoin heavy portfolio keeps its stablecoins out of net exposure only`() {
        let context = Self.stablecoinHeavy()
        let data = ExposureFeature.dashboard(context)

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.summary.totalSpot == Fixture.decimal("73000.5"))
            #expect(data.summary.totalLiabilities == 10000)
            #expect(data.summary.netTotal == Fixture.decimal("63000.5"))
            #expect(data.summary.netTotal == OverviewFeature.headline(context).total)
            #expect(data.summary.netExposure == 3000)
            #expect(data.summary.netExposureShare == 3000 / Fixture.decimal("73000.5"))

            #expect(data.categoryRows.map(\.name) == ["Stablecoins", "ETH"])
            let stablecoins = try #require(data.categoryRows.first)
            #expect(stablecoins.spotAssets == Fixture.decimal("70000.5"))
            #expect(stablecoins.liabilities == 10000)
            #expect(stablecoins.netExposure == Fixture.decimal("60000.5"))
            #expect(data.categoryHidden == nil)

            #expect(data.assetRows.map(\.symbol) == ["USDC", "DAI", "ETH"])
            #expect(data.assetRows.map(\.spotAssets) == [50000, 20000, 3000])
            #expect(data.assetRows.map(\.liabilities) == [10000, 0, 0])
            #expect(data.assetHidden == ExposureHiddenRow(
                rowCount: 1,
                isAllDust: true,
                spotAssets: Fixture.decimal("0.5"),
                liabilities: 0))
        }
    }

    /// An asset hedged by its own borrow: one row with both sides, not dust, and the Net total is
    /// the headline.
    @Test func `a hedged asset shows both sides on one row and the net total is the headline`() {
        let context = Self.hedged()
        let data = ExposureFeature.dashboard(context)

        withKnownIssue("Exposure converges on the module in the next commit") {
            let eth = try #require(data.assetRows.first { $0.symbol == "ETH" })
            #expect(eth.spotAssets == 30000)
            #expect(eth.liabilities == 29700)
            #expect(eth.netExposure == 300)
            #expect(eth.shareOfSpot == Decimal(300) / Decimal(31000))
            #expect(data.assetHidden == nil)

            #expect(data.summary.totalSpot == 31000)
            #expect(data.summary.totalLiabilities == 29700)
            #expect(data.summary.netTotal == 1300)
            #expect(data.summary.netTotal == OverviewFeature.headline(context).total)
            #expect(data.summary.netExposure == 300)
            #expect(data.categoryRows.map(\.name) == ["Stablecoins", "ETH"])
        }
    }

    // MARK: - Rows and the display filter

    /// The shared fixture's asset table: every valued asset with both sides on its row, ranked by
    /// net (ties by symbol), and the three hidden rows in the last line.
    @Test func `the asset table ranks module rows by net and ends with its hidden line`() {
        let data = ExposureFeature.dashboard(Fixture.context())

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.assetRows.map(\.symbol) == [
                "ETH", "SOL", "USDC", "OTC", "LINK", "DEGEN", "MNL", "ARB", "UNI", "PEPE", "TINY"
            ])
            #expect(data.assetRows.map(\.netExposure) == [
                7500, 1500, 1000, 250, 160, 100, 100, 90, 70, 10, Fixture.decimal("0.3")
            ])
            let eth = try #require(data.assetRows.first)
            #expect(eth.spotAssets == 9000)
            #expect(eth.liabilities == 1500)

            let hidden = try #require(data.assetEntries.last?.hidden)
            #expect(hidden == ExposureHiddenRow(
                rowCount: 3,
                isAllDust: false,
                spotAssets: Fixture.decimal("0.5"),
                liabilities: Fixture.decimal("0.4")))
            #expect(hidden.netExposure == Fixture.decimal("0.1"))
            #expect(hidden.title == "3 hidden balances")
            Self.expectTablesReconcile(data)
        }
    }

    /// U2 and F3: each table's last row is its hidden line, with the hidden gross, debt and net in
    /// the spot, liabilities and net cells. A dust holding and a dust borrow, each in a category of
    /// its own, are hidden from both tables.
    @Test func `the hidden line is the last row of each table on all three bases`() {
        let context = Fixture.context(
            tokens: [
                Fixture.token(Self.btc, "BTC", "Bitcoin", .major, coinGeckoId: "bitcoin", amount: Fixture.decimal("0.1"), usdValue: 5000),
                Fixture.token(Self.wojak, "WOJAK", "Wojak", .meme, amount: 1, usdValue: Fixture.decimal("0.5")),
                Fixture.token(Self.xmr, "XMR", "Monero", .privacy, role: .borrow, amount: 1, usdValue: Fixture.decimal("0.3"))
            ],
            livePricesUSD: ["bitcoin": 50000])
        let data = ExposureFeature.dashboard(context)
        let expected = ExposureHiddenRow(
            rowCount: 2,
            isAllDust: true,
            spotAssets: Fixture.decimal("0.5"),
            liabilities: Fixture.decimal("0.3"))

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.categoryEntries.last?.hidden == expected)
            #expect(data.assetEntries.last?.hidden == expected)
            #expect(data.categoryEntries.dropLast().allSatisfy { $0.hidden == nil })
            #expect(data.assetEntries.dropLast().allSatisfy { $0.hidden == nil })
            #expect(data.categoryRows.map(\.name) == ["BTC"])
            #expect(data.assetRows.map(\.symbol) == ["BTC"])
            #expect(expected.netExposure == Fixture.decimal("0.2"))
            #expect(expected.title == "2 small balances")
            Self.expectTablesReconcile(data)
        }
    }

    /// F1 filter value max(gross, debt). Number changes → Exposure: "$0.80 supplied against $1,000
    /// borrowed is visible".
    @Test func `a row with 0.80 supplied against 1000 borrowed is visible`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [
                Fixture.token(
                    Self.loop,
                    "LOOP",
                    "Loop",
                    .defi,
                    coinGeckoId: "loop",
                    role: .supply,
                    amount: Fixture.decimal("0.8"),
                    usdValue: Fixture.decimal("0.8")),
                Fixture.token(Self.loop, "LOOP", "Loop", .defi, coinGeckoId: "loop", role: .borrow, amount: 1000, usdValue: 1000)
            ],
            livePricesUSD: ["loop": 1]))

        withKnownIssue("Exposure converges on the module in the next commit") {
            let row = try #require(data.assetRows.first)
            #expect(data.assetRows.count == 1)
            #expect(row.spotAssets == Fixture.decimal("0.8"))
            #expect(row.liabilities == 1000)
            #expect(row.netExposure == Fixture.decimal("-999.2"))
            #expect(data.assetHidden == nil)
            #expect(data.summary.totalSpot == Fixture.decimal("0.8"))
        }
    }

    /// F1: a hedged row is judged on max(gross, debt), not on its net.
    @Test func `a row with 1000 supplied against 1000 borrowed is not dust`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [
                Fixture.token(Self.loop, "LOOP", "Loop", .defi, coinGeckoId: "loop", role: .supply, amount: 1000, usdValue: 1000),
                Fixture.token(Self.loop, "LOOP", "Loop", .defi, coinGeckoId: "loop", role: .borrow, amount: 1000, usdValue: 1000)
            ],
            livePricesUSD: ["loop": 1]))

        withKnownIssue("Exposure converges on the module in the next commit") {
            let row = try #require(data.assetRows.first)
            #expect(row.spotAssets == 1000)
            #expect(row.liabilities == 1000)
            #expect(row.netExposure == 0)
            #expect(data.assetHidden == nil)
            #expect(data.categoryHidden == nil)
        }
    }

    /// F1 and F2: each table judges its own rows. A $0.50 meme coin is dust on the asset table, but
    /// its Meme category row is above the threshold and keeps it.
    @Test func `a dust asset inside an above threshold category is hidden on the asset table only`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [
                Fixture.token(Fixture.AssetID.pepe, "PEPE", "Pepe", .meme, coinGeckoId: "pepe", amount: 1_000_000, usdValue: 9),
                Fixture.token(Self.wojak, "WOJAK", "Wojak", .meme, coinGeckoId: "wojak", amount: 1, usdValue: Fixture.decimal("0.5"))
            ],
            livePricesUSD: ["pepe": Fixture.decimal("0.00001"), "wojak": Fixture.decimal("0.5")]))

        withKnownIssue("Exposure converges on the module in the next commit") {
            let meme = try #require(data.categoryRows.first)
            #expect(data.categoryRows.map(\.name) == ["Meme"])
            #expect(meme.spotAssets == Fixture.decimal("10.5"))
            #expect(data.categoryHidden == nil)
            #expect(data.assetRows.map(\.symbol) == ["PEPE"])
            #expect(data.assetHidden == ExposureHiddenRow(
                rowCount: 1,
                isAllDust: true,
                spotAssets: Fixture.decimal("0.5"),
                liabilities: 0))
            Self.expectTablesReconcile(data)
        }
    }

    /// F2.3 (decided 2026-10-13): with Hide unpriced off, an unpriced asset shows as a 0 row on
    /// both tables. Number changes → Exposure: "With Hide unpriced off, unpriced rows now show".
    @Test func `with hide unpriced off an unpriced asset shows as a zero row on both tables`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [
                Fixture.token(Self.btc, "BTC", "Bitcoin", .major, coinGeckoId: "bitcoin", amount: Fixture.decimal("0.01"), usdValue: 500),
                Fixture.token(Self.lost, "LOST", "Lost Coin", .other, coinGeckoId: "lost-coin", amount: 10, usdValue: 0)
            ],
            settings: TokenDashboardSettings(hideUnpriced: false),
            livePricesUSD: ["bitcoin": 50000]))

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.categoryRows.map(\.name) == ["BTC", "Other Tokens"])
            #expect(data.assetRows.map(\.symbol) == ["BTC", "LOST"])
            let other = try #require(data.categoryRows.last)
            let lost = try #require(data.assetRows.last)
            #expect(other.spotAssets == 0)
            #expect(lost.spotAssets == 0)
            #expect(data.categoryHidden == nil)
            #expect(data.assetHidden == nil)
        }
    }

    /// A reward-only asset has no counted token: no row and no hidden line on either table, and it
    /// counts nothing.
    @Test func `a reward only asset has no row`() {
        let data = ExposureFeature.dashboard(Fixture.context(
            tokens: [
                Fixture.token(Self.btc, "BTC", "Bitcoin", .major, coinGeckoId: "bitcoin", amount: Fixture.decimal("0.01"), usdValue: 500),
                Fixture.token(Self.reward, "RWD", "Reward Coin", .defi, coinGeckoId: "reward-coin", role: .reward, amount: 5, usdValue: 10)
            ],
            livePricesUSD: ["bitcoin": 50000, "reward-coin": 2]))

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(data.categoryRows.map(\.name) == ["BTC"])
            #expect(data.assetRows.map(\.symbol) == ["BTC"])
            #expect(data.categoryHidden == nil)
            #expect(data.assetHidden == nil)
            #expect(data.summary.totalSpot == 500)
        }
    }

    // MARK: - % of spot

    /// Decided 2026-10-13: "% of spot" is net over the full Spot total, and "—" when Spot ≤ 0.
    @Test func `percent of spot divides by the full spot total`() {
        let data = ExposureFeature.dashboard(Fixture.context())

        withKnownIssue("Exposure converges on the module in the next commit") {
            let eth = try #require(data.assetRows.first { $0.symbol == "ETH" })
            let stablecoins = try #require(data.categoryRows.first { $0.name == "Stablecoins" })
            #expect(eth.shareOfSpot == 7500 / Fixture.decimal("12280.8"))
            #expect(stablecoins.shareOfSpot == Fixture.decimal("1000.1") / Fixture.decimal("12280.8"))
        }
    }

    @Test func `percent of spot is a dash when spot is not positive`() {
        let context = Fixture.context(
            tokens: [Fixture.token(Self.usdc, "USDC", "USD Coin", .stablecoin, coinGeckoId: "usd-coin", role: .borrow, amount: 100, usdValue: 100)],
            livePricesUSD: ["usd-coin": 1])
        let data = ExposureFeature.dashboard(context)

        withKnownIssue("Exposure converges on the module in the next commit") {
            let row = try #require(data.assetRows.first)
            #expect(row.liabilities == 100)
            #expect(row.shareOfSpot == nil)
            #expect(data.categoryRows.first?.shareOfSpot == nil)
            #expect(data.summary.netTotal == -100)
            #expect(data.summary.netTotal == OverviewFeature.headline(context).total)
            #expect(data.summary.netExposureShare == nil)

            let empty = ExposureFeature.dashboard(Fixture.context(tokens: []))
            #expect(empty.summary == ExposureSummary(totalSpot: 0, totalLiabilities: 0, netTotal: 0, netExposure: 0, netExposureShare: nil))
            #expect(empty.categoryEntries.isEmpty)
            #expect(empty.assetEntries.isEmpty)
        }
    }

    // MARK: - Display rate

    /// The rate applies once, after the filter, and the threshold stays USD: the rows and the
    /// hidden line are the USD ones scaled.
    @Test func `values are converted once at a non usd rate`() {
        let usd = ExposureFeature.dashboard(Fixture.context())
        let chf = ExposureFeature.dashboard(Fixture.context(rate: Fixture.decimal("0.9")))
        let rate = Fixture.decimal("0.9")

        withKnownIssue("Exposure converges on the module in the next commit") {
            #expect(chf.assetRows.map(\.symbol) == usd.assetRows.map(\.symbol))
            #expect(chf.assetRows.map(\.spotAssets) == usd.assetRows.map { $0.spotAssets * rate })
            #expect(chf.assetRows.map(\.liabilities) == usd.assetRows.map { $0.liabilities * rate })
            #expect(chf.assetRows.map(\.shareOfSpot) == usd.assetRows.map(\.shareOfSpot))
            #expect(chf.assetHidden?.spotAssets == Fixture.decimal("0.45"))
            #expect(chf.assetHidden?.liabilities == Fixture.decimal("0.36"))
            #expect(chf.summary.netTotal == Fixture.decimal("10780.4") * rate)
            #expect(chf.summary.netExposure == Fixture.decimal("9780.3") * rate)
        }
    }

    // MARK: - Helpers

    /// A7: on each table, the visible rows plus the hidden line give Spot, Liabilities and the Net
    /// total.
    private static func expectTablesReconcile(_ data: ExposureDashboardData, sourceLocation: SourceLocation = #_sourceLocation) {
        let tables: [[(spot: Decimal, liabilities: Decimal)]] = [
            data.categoryEntries.map(\.values),
            data.assetEntries.map(\.values)
        ]
        for table in tables {
            let spot = table.reduce(Decimal.zero) { $0 + $1.spot }
            let liabilities = table.reduce(Decimal.zero) { $0 + $1.liabilities }
            #expect(spot == data.summary.totalSpot, sourceLocation: sourceLocation)
            #expect(liabilities == data.summary.totalLiabilities, sourceLocation: sourceLocation)
            #expect(spot - liabilities == data.summary.netTotal, sourceLocation: sourceLocation)
        }
    }

    private static let usdc = Fixture.uuid(701)
    private static let dai = Fixture.uuid(702)
    private static let eth = Fixture.uuid(703)
    private static let usdt = Fixture.uuid(704)
    private static let btc = Fixture.uuid(705)
    private static let wojak = Fixture.uuid(706)
    private static let xmr = Fixture.uuid(707)
    private static let loop = Fixture.uuid(708)
    private static let lost = Fixture.uuid(709)
    private static let reward = Fixture.uuid(710)

    /// $50,000 USDC held and $10,000 borrowed, $20,000 DAI supplied, a $0.50 USDT dust balance and
    /// 1 ETH.
    private static func stablecoinHeavy() -> ValuationContext {
        Fixture.context(
            inputs: [
                Fixture.input(
                    601,
                    .wallet,
                    Fixture.token(usdc, "USDC", "USD Coin", .stablecoin, coinGeckoId: "usd-coin", amount: 50000, usdValue: 50000)),
                Fixture.input(602, .aave, Fixture.token(
                    dai, "DAI", "Dai", .stablecoin, coinGeckoId: "dai", role: .supply, amount: 20000, usdValue: 20000)),
                Fixture.input(603, .aave, Fixture.token(
                    usdc, "USDC", "USD Coin", .stablecoin, coinGeckoId: "usd-coin", role: .borrow, amount: 10000, usdValue: 10000)),
                Fixture.input(604, .wallet, Fixture.token(eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", amount: 1, usdValue: 3000)),
                Fixture.input(605, .wallet, Fixture.token(
                    usdt, "USDT", "Tether", .stablecoin, coinGeckoId: "tether", amount: Fixture.decimal("0.5"), usdValue: Fixture.decimal("0.5")))
            ],
            livePricesUSD: ["usd-coin": 1, "dai": 1, "ethereum": 3000, "tether": 1],
            liveChanges24h: [:],
            historical: .empty)
    }

    /// 10 ETH supplied against 9.9 ETH borrowed, and $1,000 USDC.
    private static func hedged() -> ValuationContext {
        Fixture.context(
            inputs: [
                Fixture.input(
                    611,
                    .aave,
                    Fixture.token(eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", role: .supply, amount: 10, usdValue: 30000)),
                Fixture.input(612, .aave, Fixture.token(
                    eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", role: .borrow, amount: Fixture.decimal("9.9"), usdValue: 29700)),
                Fixture.input(
                    613,
                    .wallet,
                    Fixture.token(usdc, "USDC", "USD Coin", .stablecoin, coinGeckoId: "usd-coin", amount: 1000, usdValue: 1000))
            ],
            livePricesUSD: ["usd-coin": 1, "ethereum": 3000],
            liveChanges24h: [:],
            historical: .empty)
    }
}

private extension ExposureTableEntry {
    var values: (spot: Decimal, liabilities: Decimal) {
        switch self {
        case let .row(row): (row.spotAssets, row.liabilities)
        case let .hidden(row): (row.spotAssets, row.liabilities)
        }
    }
}
