import Foundation
@testable import Portu
import PortuCore
import Testing

/// The All Assets seams (S5, A7, F1–F4, T2) over the shared fixture and variants of it. Every value
/// is worked out by hand in USD from the fixture tables.
///
/// Platforms on the shared fixture: Idle / Wallet 7690.8 (Main Wallet 7340.8 + Degen Wallet 350;
/// the Scam Wallet's only token is ignored), Lido 1500 (the reward counts 0), Aave V3 1499.6 and
/// Arbitrum Vesting 90. Networks: ethereum 8840.4 (Main Wallet + Aave V3), solana 1500, degen 350,
/// arbitrum 90, and no base row. Neither list hides anything; the Assets tab hides DAI (0.5 dust),
/// BAD (unpriced) and the USDT borrow (0.4 dust).
enum AllAssetsSeamFixture {
    typealias Fixture = PortfolioValuationFixture

    static let protocolNames: [UUID: String] = [
        Fixture.PositionID.aave: "Aave V3",
        Fixture.PositionID.lido: "Lido",
        Fixture.PositionID.vesting: "Arbitrum Vesting"
    ]

    /// A sync-valued token (no price ID) of an asset of its own, in a position of its own unless
    /// `position` names a shared one.
    static func input(
        _ number: Int,
        protocolID: String?,
        chain: Chain? = .ethereum,
        positionType: PositionType = .lending,
        role: TokenRole = .balance,
        usdValue: Decimal,
        position: Int? = nil,
        asset: Int? = nil) -> ValuationInput {
        let assetNumber = asset ?? number
        return ValuationInput(
            tokenId: Fixture.uuid(9000 + number),
            token: Fixture.token(
                Fixture.uuid(7000 + assetNumber),
                String(format: "T%03d", assetNumber),
                "Token \(assetNumber)",
                .other,
                role: role,
                amount: 1,
                usdValue: usdValue),
            position: PositionContext(
                positionId: Fixture.uuid(8000 + (position ?? number)),
                positionType: positionType,
                accountId: Fixture.mainAccount,
                chain: chain,
                protocolId: protocolID))
    }

    static func context(
        _ inputs: [ValuationInput],
        settings: TokenDashboardSettings = .defaults,
        rate: Decimal = 1) -> ValuationContext {
        Fixture.context(rate: rate, settings: settings, inputs: inputs, livePricesUSD: [:], liveChanges24h: [:], historical: .empty)
    }
}

// MARK: - Assets

struct AllAssetsAssetsSeamTests {
    private typealias Fixture = PortfolioValuationFixture

    /// S5 and AGENT-DECIDED 5: rows are module rows keyed by asset ID. Number changes → All Assets:
    /// "Identity mappings apply", "An implausible onchain price counts 0", "Sync-only tokens show at
    /// their sync value", "Price = Σ value ÷ Σ amount (V5)".
    @Test func `rows are the module's asset rows`() {
        let data = AllAssetsFeature.assets(Fixture.context(), searchText: "")
        let values = Dictionary(uniqueKeysWithValues: data.rows.map { ($0.id, $0.value) })

        #expect(values == [
            Fixture.AssetID.usdc: 1000,
            Fixture.AssetID.eth: 7500,
            Fixture.AssetID.pepe: 10,
            Fixture.AssetID.manual: 100,
            Fixture.AssetID.link: 160,
            Fixture.AssetID.uni: 70,
            Fixture.AssetID.tiny: Fixture.decimal("0.3"),
            Fixture.AssetID.degen: 100,
            Fixture.AssetID.otc: 250,
            Fixture.AssetID.sol: 1500,
            Fixture.AssetID.arb: 90
        ])
        let eth = data.rows.first { $0.id == Fixture.AssetID.eth }
        #expect(eth?.netAmount == Fixture.decimal("2.5"))
        #expect(eth?.price == 3000)
        #expect(eth?.source == .live)
    }

    /// V5 and AGENT-DECIDED 9: each row's price and source; the clock marks `.sync` only.
    @Test func `prices follow V5 and carry their source`() {
        let rows = AllAssetsFeature.assets(Fixture.context(), searchText: "").rows
        func row(_ id: UUID) -> AssetRowData? {
            rows.first { $0.id == id }
        }

        #expect(row(Fixture.AssetID.manual)?.price == 2)
        #expect(row(Fixture.AssetID.manual)?.source == .manual)
        #expect(row(Fixture.AssetID.link)?.price == 16)
        #expect(row(Fixture.AssetID.link)?.source == .close)
        #expect(row(Fixture.AssetID.degen)?.price == Fixture.decimal("0.01"))
        #expect(row(Fixture.AssetID.degen)?.source == .live)
        #expect(row(Fixture.AssetID.uni)?.price == 7)
        #expect(row(Fixture.AssetID.uni)?.source == .sync)
        #expect(row(Fixture.AssetID.otc)?.price == 50)
        #expect(row(Fixture.AssetID.otc)?.source == .sync)
        // The reward is not counted, so SOL's price is its stake's.
        #expect(row(Fixture.AssetID.sol)?.price == 150)
    }

    /// A7 and F3: the hidden line holds DAI, BAD and the USDT borrow; visible rows + the line = the
    /// Overview headline.
    @Test func `the hidden line and the total reconcile with the headline`() {
        let context = Fixture.context()
        let data = AllAssetsFeature.assets(context, searchText: "")
        let visible = data.rows.reduce(Decimal.zero) { $0 + $1.value }

        #expect(data.hidden == AllAssetsHiddenRow(rowCount: 3, isAllDust: false, value: Fixture.decimal("0.1"), share: nil))
        #expect(visible == Fixture.decimal("10780.3"))
        #expect(data.total == Fixture.decimal("10780.4"))
        #expect(data.total == OverviewFeature.headline(context).total)
    }

    /// F2.3: with Hide unpriced off, BAD shows with no price and value 0; only dust is hidden.
    @Test func `an unpriced row shows with no price when hide unpriced is off`() {
        let settings = TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: false, hideDust: true)
        let data = AllAssetsFeature.assets(Fixture.context(settings: settings), searchText: "")
        let bad = data.rows.first { $0.id == Fixture.AssetID.bad }

        #expect(bad?.price == nil)
        #expect(bad?.value == 0)
        #expect(bad?.source == nil)
        #expect(data.hidden == AllAssetsHiddenRow(rowCount: 2, isAllDust: true, value: Fixture.decimal("0.1"), share: nil))
    }

    /// T1 units and F2: the rate is applied once; the dust threshold stays a USD amount. At rate 2
    /// DAI shows 1.0 but is still 0.5 USD dust. Number changes → All Assets: "The rate is applied
    /// once" and "Dust is judged per asset row against an unscaled USD threshold".
    @Test func `the rate is applied once and the threshold is not scaled`() {
        let data = AllAssetsFeature.assets(Fixture.context(rate: 2), searchText: "")
        let eth = data.rows.first { $0.id == Fixture.AssetID.eth }

        #expect(eth?.value == 15000)
        #expect(eth?.price == 6000)
        #expect(!data.rows.contains { $0.id == Fixture.AssetID.dai })
        #expect(data.hidden?.value == Fixture.decimal("0.2"))
        #expect(data.total == Fixture.decimal("21560.8"))
    }

    /// U2: a search narrows the rows and drops the hidden line; clearing it brings the line back.
    /// The total never changes.
    @Test func `searching removes the hidden line and never changes the total`() {
        let context = Fixture.context()
        let searched = AllAssetsFeature.assets(context, searchText: "eth")
        let cleared = AllAssetsFeature.assets(context, searchText: "")

        #expect(searched.hidden == nil)
        #expect(searched.total == cleared.total)
        #expect(searched.rows.map(\.symbol) == ["ETH"])
        #expect(cleared.hidden?.rowCount == 3)
        #expect(cleared.entries(sortedBy: .value, ascending: false).last?.hidden == cleared.hidden)
        #expect(searched.total == Fixture.decimal("10780.4"))
    }

    /// U2: the hidden line is appended after any user sort.
    @Test(arguments: AssetSortColumn.allCases, [true, false])
    func `the hidden line stays last whatever the sort`(_ column: AssetSortColumn, ascending: Bool) {
        let data = AllAssetsFeature.assets(Fixture.context(), searchText: "")
        let entries = data.entries(sortedBy: column, ascending: ascending)

        #expect(entries.dropLast().allSatisfy { $0.row != nil })
        #expect(entries.count == data.rows.count + 1)
        #expect(entries.last?.hidden != nil)
    }

    /// F3: a portfolio of dust only has no visible row and a non-empty hidden line.
    @Test func `an all-dust portfolio shows only the hidden line`() {
        let context = AllAssetsSeamFixture.context([
            AllAssetsSeamFixture.input(1, protocolID: nil, positionType: .idle, usdValue: Fixture.decimal("0.5")),
            AllAssetsSeamFixture.input(2, protocolID: nil, positionType: .idle, usdValue: Fixture.decimal("0.3"))
        ])
        let data = AllAssetsFeature.assets(context, searchText: "")

        #expect(data.rows.isEmpty)
        #expect(data.entries(sortedBy: .value, ascending: false) == [
            .hidden(AllAssetsHiddenRow(rowCount: 2, isAllDust: true, value: Fixture.decimal("0.8"), share: nil))
        ])
        #expect(data.total == Fixture.decimal("0.8"))
    }

    /// AGENT-DECIDED 9: a missing price exports as an empty cell.
    @Test func `CSV writes an empty cell for a missing price`() {
        let row = AssetRowData(
            id: UUID(),
            symbol: "BAD",
            name: "Bad Price",
            category: .other,
            netAmount: 100,
            price: nil,
            value: 0,
            source: nil)

        let lines = AllAssetsFeature.generateCSV(from: [row]).components(separatedBy: "\n")

        #expect(lines.count == 2)
        #expect(lines.last?.hasSuffix(",100,,0") == true)
    }
}

// MARK: - Platforms

struct AllAssetsPlatformsSeamTests {
    private typealias Fixture = PortfolioValuationFixture
    private typealias Seam = AllAssetsSeamFixture

    /// S5, A7, F4 and AGENT-DECIDED 8 on the shared fixture. Number changes → All Assets: Platforms
    /// "follow the shared valuation, not the stored sync sum", "exclude ignored tokens and equal the
    /// Overview total", and "shares use largest-remainder rounding".
    @Test func `platforms are module sums with largest remainder shares`() {
        let context = Fixture.context()
        let data = AllAssetsFeature.platforms(context, protocolNames: Seam.protocolNames)

        #expect(data.rows == [
            PlatformRowData(
                id: .idle,
                name: "Idle / Wallet",
                share: Fixture.decimal("0.714"),
                networkCount: 2,
                positionCount: 2,
                balance: Fixture.decimal("7690.8")),
            PlatformRowData(
                id: .protocolID("lido"),
                name: "Lido",
                share: Fixture.decimal("0.139"),
                networkCount: 1,
                positionCount: 1,
                balance: 1500),
            PlatformRowData(
                id: .protocolID("aave-v3"),
                name: "Aave V3",
                share: Fixture.decimal("0.139"),
                networkCount: 1,
                positionCount: 1,
                balance: Fixture.decimal("1499.6")),
            PlatformRowData(
                id: .protocolID("arbitrum-vesting"),
                name: "Arbitrum Vesting",
                share: Fixture.decimal("0.008"),
                networkCount: 1,
                positionCount: 1,
                balance: 90)
        ])
        #expect(data.total == Fixture.decimal("10780.4"))
        #expect(data.total == OverviewFeature.headline(context).total)
        #expect(data.hidden == nil)
    }

    /// F4's example: one row at 95.2% and 120 rows at 0.04% show 95.2%, 48 rows at 0.1% and 72 at
    /// 0.0%; the old residual-to-largest rule showed 100.0%.
    @Test func `shares follow the F4 example`() {
        let inputs = [Seam.input(0, protocolID: "big", usdValue: 95200)]
            + (1 ... 120).map { Seam.input($0, protocolID: String(format: "p%03d", $0), usdValue: 40) }
        let data = AllAssetsFeature.platforms(Seam.context(inputs))
        let shares = data.rows.map(\.share)

        #expect(data.rows.count == 121)
        #expect(shares.first == Fixture.decimal("0.952"))
        #expect(shares.filter { $0 == Fixture.decimal("0.001") }.count == 48)
        #expect(shares.dropFirst().filter { $0 == 0 }.count == 72)
        #expect(shares.compactMap(\.self).reduce(Decimal.zero, +) == 1)
    }

    /// F4 with the hidden line inside it: 119 visible rows at 0.04% and a hidden line of 100 dust
    /// platforms worth 0.04% together. The line takes part in the rounding as the last row, so it
    /// shows 0.0% and the 48 steps go to the earlier rows.
    @Test func `the F4 example counts the hidden line`() {
        let inputs = [Seam.input(0, protocolID: "big", usdValue: 95200)]
            + (1 ... 119).map { Seam.input($0, protocolID: String(format: "p%03d", $0), usdValue: 40) }
            + (200 ..< 300).map { Seam.input($0, protocolID: "dust-\($0)", usdValue: Fixture.decimal("0.4")) }
        let data = AllAssetsFeature.platforms(Seam.context(inputs))
        let shares = data.rows.map(\.share)

        #expect(data.rows.count == 120)
        #expect(shares.first == Fixture.decimal("0.952"))
        #expect(shares.filter { $0 == Fixture.decimal("0.001") }.count == 48)
        #expect(shares.dropFirst().filter { $0 == 0 }.count == 71)
        #expect(data.hidden == AllAssetsHiddenRow(rowCount: 100, isAllDust: true, value: 40, share: 0))
        #expect(data.total == 100_000)
    }

    /// F4: rows and the hidden line sum to 100%. Rounding the visible rows alone would show 65.2%
    /// and 34.8%.
    @Test func `the hidden line carries its share`() {
        let data = AllAssetsFeature.platforms(Seam.context([
            Seam.input(1, protocolID: "aave", usdValue: 6),
            Seam.input(2, protocolID: "compound", usdValue: Fixture.decimal("3.2")),
            Seam.input(3, protocolID: "dust-a", usdValue: Fixture.decimal("0.4")),
            Seam.input(4, protocolID: "dust-b", usdValue: Fixture.decimal("0.4"))
        ]))

        #expect(data.rows.map(\.share) == [Fixture.decimal("0.6"), Fixture.decimal("0.32")])
        #expect(data.hidden == AllAssetsHiddenRow(
            rowCount: 2,
            isAllDust: true,
            value: Fixture.decimal("0.8"),
            share: Fixture.decimal("0.08")))
        #expect(data.entries.last?.hidden?.share == Fixture.decimal("0.08"))
    }

    /// F1: a looped lending platform ($50,000 supplied against $49,999.20 borrowed) is not dust,
    /// while a $0.50 platform is. Reward-only and ignored platforms vanish. Number changes → All
    /// Assets: "A hedged protocol is not dust" and "ignored-only, reward-only and empty positions
    /// vanish".
    @Test func `a hedged platform is not dust and reward-only platforms vanish`() throws {
        let data = AllAssetsFeature.platforms(Seam.context([
            Seam.input(1, protocolID: "loop", usdValue: 50000, position: 1, asset: 1),
            Seam.input(2, protocolID: "loop", role: .borrow, usdValue: Fixture.decimal("49999.2"), position: 1, asset: 1),
            Seam.input(3, protocolID: "dust-farm", positionType: .farming, usdValue: Fixture.decimal("0.5")),
            Seam.input(4, protocolID: "rewards", positionType: .staking, role: .reward, usdValue: 30)
        ]))

        let loop = try #require(data.rows.first { $0.id == .protocolID("loop") })
        #expect(loop.balance == Fixture.decimal("0.8"))
        #expect(data.rows.map(\.id) == [.protocolID("loop")])
        #expect(data.hidden?.rowCount == 1)
        #expect(data.hidden?.value == Fixture.decimal("0.5"))
        #expect(data.total == Fixture.decimal("1.3"))
    }

    /// F4: a list whose total is not positive shows "—" for every share. Number changes → All
    /// Assets: shares "show '—' for an empty list or a total that is not positive".
    @Test func `shares are absent when the total is not positive`() {
        let data = AllAssetsFeature.platforms(Seam.context([
            Seam.input(1, protocolID: "aave", usdValue: 100),
            Seam.input(2, protocolID: "compound", role: .borrow, usdValue: 150)
        ]))

        #expect(data.rows.count == 2)
        #expect(data.rows.allSatisfy { $0.share == nil })
        #expect(data.total == -50)
    }

    /// F4: a missing share reads "—", a share reads to 0.1%.
    @Test func `share text`() {
        #expect(AllAssetsFormat.share(nil) == "—")
        #expect(AllAssetsFormat.share(Fixture.decimal("0.952")) == Fixture.decimal("0.952").formatted(.percent.precision(.fractionLength(1))))
    }

    /// AGENT-DECIDED 8: the name is the lowest protocol name of the platform's positions; equal
    /// balances order by name, then key. A dust platform puts a hidden line under them.
    @Test func `platform names and ties are deterministic`() {
        let inputs = [
            Seam.input(1, protocolID: "aave-v3", usdValue: 50),
            Seam.input(2, protocolID: "aave-v3", usdValue: 50),
            Seam.input(3, protocolID: "zeta", usdValue: 100),
            Seam.input(4, protocolID: "alpha", usdValue: 100),
            Seam.input(5, protocolID: "nameless", usdValue: 100),
            Seam.input(6, protocolID: "dust-farm", usdValue: Fixture.decimal("0.5"))
        ]
        let names = [
            Fixture.uuid(8001): "Aave V3",
            Fixture.uuid(8002): "Aave",
            Fixture.uuid(8003): "Beta",
            Fixture.uuid(8004): "Beta"
        ]

        for order in [inputs, inputs.reversed()] {
            let data = AllAssetsFeature.platforms(Seam.context(order), protocolNames: names)
            #expect(data.rows.map(\.name) == ["Aave", "Beta", "Beta", "nameless"])
            #expect(data.rows.map(\.id) == [.protocolID("aave-v3"), .protocolID("alpha"), .protocolID("zeta"), .protocolID("nameless")])
            #expect(data.rows.first?.positionCount == 2)
            #expect(data.hidden?.rowCount == 1)
        }
    }
}

// MARK: - Networks

struct AllAssetsNetworksSeamTests {
    private typealias Fixture = PortfolioValuationFixture
    private typealias Seam = AllAssetsSeamFixture

    /// S5, A7, F4, T4 and AGENT-DECIDED 8 on the shared fixture: base, whose only token is ignored,
    /// has no row. Number changes → All Assets: Networks "follow the shared valuation" and "exclude
    /// ignored tokens".
    @Test func `networks are module sums with largest remainder shares`() {
        let context = Fixture.context()
        let data = AllAssetsFeature.networks(context)

        #expect(data.rows == [
            NetworkRowData(id: .ethereum, name: "Ethereum", share: Fixture.decimal("0.82"), positionCount: 2, balance: Fixture.decimal("8840.4")),
            NetworkRowData(id: .solana, name: "Solana", share: Fixture.decimal("0.139"), positionCount: 1, balance: 1500),
            NetworkRowData(id: .degen, name: "Degen", share: Fixture.decimal("0.033"), positionCount: 1, balance: 350),
            NetworkRowData(id: .arbitrum, name: "Arbitrum", share: Fixture.decimal("0.008"), positionCount: 1, balance: 90)
        ])
        #expect(data.total == Fixture.decimal("10780.4"))
        #expect(data.total == OverviewFeature.headline(context).total)
        #expect(data.hidden == nil)
    }

    /// F3 and F4: dust chains fold into the hidden line, which carries its share; an off-chain
    /// position has its own row.
    @Test func `dust chains fold into the hidden line with its share`() {
        let data = AllAssetsFeature.networks(Seam.context([
            Seam.input(1, protocolID: nil, chain: .ethereum, positionType: .idle, usdValue: 6),
            Seam.input(2, protocolID: "desk", chain: nil, positionType: .other, usdValue: Fixture.decimal("3.2")),
            Seam.input(3, protocolID: nil, chain: .base, positionType: .idle, usdValue: Fixture.decimal("0.4")),
            Seam.input(4, protocolID: nil, chain: .optimism, positionType: .idle, usdValue: Fixture.decimal("0.4"))
        ]))

        let offChain = data.rows.first { $0.id == nil }
        #expect(offChain?.name == "Off-chain / Custodial")
        #expect(data.rows.map(\.id) == [.ethereum, nil])
        #expect(data.rows.map(\.share) == [Fixture.decimal("0.6"), Fixture.decimal("0.32")])
        #expect(data.hidden == AllAssetsHiddenRow(
            rowCount: 2,
            isAllDust: true,
            value: Fixture.decimal("0.8"),
            share: Fixture.decimal("0.08")))
    }
}

// MARK: - Totals

/// S5 and T2: each tab's total is the Overview headline, whatever the filter settings, the rate or
/// the search.
struct AllAssetsTotalsTests {
    private typealias Fixture = PortfolioValuationFixture

    @Test(arguments: [
        TokenDashboardSettings.defaults,
        TokenDashboardSettings(minimumDashboardValue: 1, hideUnpriced: false, hideDust: false),
        TokenDashboardSettings(minimumDashboardValue: 5000, hideUnpriced: true, hideDust: true)
    ])
    func `every tab total is the overview headline`(_ settings: TokenDashboardSettings) {
        let context = Fixture.context(rate: Fixture.decimal("0.9"), settings: settings)
        let headline = OverviewFeature.headline(context).total

        #expect(AllAssetsFeature.assets(context, searchText: "").total == headline)
        #expect(AllAssetsFeature.assets(context, searchText: "sol").total == headline)
        #expect(AllAssetsFeature.platforms(context, protocolNames: AllAssetsSeamFixture.protocolNames).total == headline)
        #expect(AllAssetsFeature.networks(context).total == headline)
    }
}
