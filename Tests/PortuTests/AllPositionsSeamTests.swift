import Foundation
@testable import Portu
import PortuCore
import Testing

/// The All Positions page seam (S6, A7, T2, T4, U4) over the shared fixture and variants of it.
/// Every value is worked out by hand in USD from the fixture table.
///
/// Cards: Main Wallet 7340.8, Degen Wallet 350, Aave V3 1499.6 (3000 − 1500 − 0.4), Lido 1500 (the
/// reward counts 0), Arbitrum Vesting 90 and Scam Wallet 0 (ignored). Sections: Idle 7690.8 (Main,
/// Degen and Scam Wallet), Lending 1499.6, Staking 1500, Vesting 90; Σ = 10,780.4, the headline.
enum AllPositionsSeamFixture {
    typealias Fixture = PortfolioValuationFixture

    static let cards: [AllPositionsCardInfo] = [
        card(.wallet),
        card(.degenWallet),
        card(.aave, name: "Aave V3"),
        card(.lido, name: "Lido"),
        card(.vesting, name: "Arbitrum Vesting"),
        card(.scamWallet)
    ]

    static func card(_ slot: Fixture.PositionSlot, name: String? = nil) -> AllPositionsCardInfo {
        card(slot.context, name: name)
    }

    static func card(_ position: PositionContext, name: String? = nil) -> AllPositionsCardInfo {
        AllPositionsCardInfo(
            id: position.positionId,
            positionType: position.positionType,
            protocolId: position.protocolId,
            protocolName: name,
            chain: position.chain,
            healthFactor: nil)
    }

    /// A position of its own holding one sync-valued token (no price ID) of an asset of its own.
    static func syncPosition(
        _ number: Int,
        type: PositionType = .lending,
        protocolID: String?,
        usdValue: Decimal) -> ValuationInput {
        ValuationInput(
            tokenId: Fixture.uuid(9000 + number),
            token: Fixture.token(
                Fixture.uuid(7000 + number),
                String(format: "T%03d", number),
                "Token \(number)",
                .other,
                amount: 1,
                usdValue: usdValue),
            position: PositionContext(
                positionId: Fixture.uuid(8000 + number),
                positionType: type,
                accountId: Fixture.mainAccount,
                chain: .ethereum,
                protocolId: protocolID))
    }

    static func page(
        _ context: ValuationContext = Fixture.context(),
        cards: [AllPositionsCardInfo] = cards,
        filter: AllPositionsFilter = .all) -> AllPositionsPage {
        AllPositionsFeature.page(context, cards: cards, filter: filter)
    }

    struct RowValue: Equatable {
        let state: TokenRowState
        let value: Decimal?
    }

    static func cardTotals(_ page: AllPositionsPage) -> [UUID: Decimal] {
        Dictionary(uniqueKeysWithValues: page.sections.flatMap(\.cards).map { ($0.id, $0.total) })
    }

    static func rows(_ page: AllPositionsPage) -> [UUID: RowValue] {
        Dictionary(uniqueKeysWithValues: page.sections.flatMap(\.cards).flatMap(\.rows).map {
            ($0.id, RowValue(state: $0.state, value: $0.value))
        })
    }

    /// Whether every shown section's total is the sum of its shown cards.
    static func sectionsSumTheirCards(_ page: AllPositionsPage) -> Bool {
        page.sections.allSatisfy { section in
            section.total == section.cards.reduce(Decimal.zero) { $0 + $1.total }
        }
    }
}

struct AllPositionsSeamTests {
    typealias Fixture = PortfolioValuationFixture
    typealias Seam = AllPositionsSeamFixture

    /// S6: a card is Σ its tokens' contributions, at the shared valuation (V1). A borrow subtracts,
    /// the reward and the ignored SCAM count 0, and BAD's implausible price counts 0.
    @Test func `a card is the sum of its tokens' contributions`() {
        let page = Seam.page()
        let expected: [UUID: Decimal] = [
            Fixture.PositionID.wallet: Fixture.decimal("7340.8"),
            Fixture.PositionID.degenWallet: 350,
            Fixture.PositionID.aave: Fixture.decimal("1499.6"),
            Fixture.PositionID.lido: 1500,
            Fixture.PositionID.vesting: 90,
            Fixture.PositionID.scamWallet: 0
        ]

        #expect(Seam.cardTotals(page) == expected)
    }

    /// S6, A7: a section is Σ its cards; sections in type order, cards in input order.
    @Test func `a section is the sum of its cards`() {
        let page = Seam.page()

        #expect(page.sections.map(\.type) == [.idle, .lending, .staking, .vesting])
        #expect(page.sections.map { $0.cards.map(\.id) } == [
            [Fixture.PositionID.wallet, Fixture.PositionID.degenWallet, Fixture.PositionID.scamWallet],
            [Fixture.PositionID.aave],
            [Fixture.PositionID.lido],
            [Fixture.PositionID.vesting]
        ])
        #expect(page.sections.map(\.total) == [Fixture.decimal("7690.8"), Fixture.decimal("1499.6"), 1500, 90])
        #expect(Seam.sectionsSumTheirCards(page))
    }

    /// S6, A7: under a protocol filter a section is Σ its **shown** cards. A second lending
    /// position under another protocol ($200 of USDC at live 1, $190 at sync) shares the Lending
    /// section; filtered to Aave V3, the section holds the Aave card alone.
    @Test func `a section is the sum of its shown cards under a protocol filter`() {
        let compoundToken = Fixture.token(
            Fixture.AssetID.usdc, "USDC", "USD Coin", .stablecoin, coinGeckoId: "usd-coin", role: .supply, amount: 200, usdValue: 190)
        let compound = PositionContext(
            positionId: Fixture.uuid(8500),
            positionType: .lending,
            accountId: Fixture.mainAccount,
            chain: .ethereum,
            protocolId: "compound")
        let inputs = Fixture.inputs + [ValuationInput(tokenId: Fixture.uuid(8501), token: compoundToken, position: compound)]
        let cards = Seam.cards + [Seam.card(compound, name: "Compound")]
        let context = Fixture.context(inputs: inputs)

        let aaveOnly = Seam.page(context, cards: cards, filter: AllPositionsFilter(protocolFilter: .specific("aave-v3")))
        let unfiltered = Seam.page(context, cards: cards)
        let lending = unfiltered.sections.first { $0.type == .lending }
        let walletLending = Seam.page(context, cards: cards, filter: AllPositionsFilter(type: .lending, protocolFilter: .none))

        #expect(aaveOnly.sections.map(\.type) == [.lending])
        #expect(aaveOnly.sections.map { $0.cards.map(\.id) } == [[Fixture.PositionID.aave]])
        #expect(lending?.cards.map(\.id) == [Fixture.PositionID.aave, compound.positionId])
        #expect(walletLending.sections.isEmpty)
        #expect(aaveOnly.sections.map(\.total) == [Fixture.decimal("1499.6")])
        #expect(lending?.total == Fixture.decimal("1699.6"))
        #expect(Seam.sectionsSumTheirCards(aaveOnly))
        #expect(Seam.sectionsSumTheirCards(unfiltered))
    }

    /// S6, A7: a sidebar option is Σ its cards, and "All" is the Overview headline total over the
    /// same inputs. The options cover every active position whatever the filter.
    @Test func `sidebar options sum their cards and All is the headline total`() {
        let context = Fixture.context()
        let page = Seam.page(context)
        let filtered = Seam.page(context, filter: AllPositionsFilter(type: .lending, protocolFilter: .specific("aave-v3")))

        #expect(page.typeOptions.map(\.type) == [nil, .idle, .lending, .staking, .vesting])
        #expect(page.typeOptions.map(\.label) == ["All", "Idle", "Lending", "Staking", "Vesting"])
        #expect(filtered.typeOptions == page.typeOptions)
        #expect(filtered.protocolOptions == page.protocolOptions)
        // Lido's $1,500 now outranks Aave V3's $1,499.60.
        #expect(page.protocolOptions.map(\.filter) == [.none, .specific("lido"), .specific("aave-v3"), .specific("arbitrum-vesting")])
        #expect(page.protocolOptions.map(\.name) == ["Wallet", "Lido", "Aave V3", "Arbitrum Vesting"])
        #expect(page.typeOptions.first?.total == OverviewFeature.headline(context).total)
        #expect(page.typeOptions.map(\.total) == [
            Fixture.decimal("10780.4"), Fixture.decimal("7690.8"), Fixture.decimal("1499.6"), 1500, 90
        ])
        #expect(page.protocolOptions.map(\.total) == [Fixture.decimal("7690.8"), 1500, Fixture.decimal("1499.6"), 90])
    }

    /// The sidebar orders equal totals by name, then protocol ID, and names an option after the
    /// lowest protocol name of its positions (AGENT-DECIDED 8).
    @Test func `sidebar ties order by name then protocol ID`() {
        let inputs = [
            Seam.syncPosition(1, protocolID: "p-beta", usdValue: 100),
            Seam.syncPosition(2, protocolID: "p-2", usdValue: 100),
            Seam.syncPosition(3, protocolID: "p-1", usdValue: 100),
            Seam.syncPosition(4, protocolID: "p-alpha", usdValue: 60),
            Seam.syncPosition(5, protocolID: "p-alpha", usdValue: 40)
        ]
        let names = ["Beta", "Same", "Same", "Zed", "Able"]
        let cards = zip(inputs, names).map { Seam.card($0.position, name: $1) }
        let context = Fixture.context(inputs: inputs, livePricesUSD: [:], liveChanges24h: [:], historical: .empty)

        let page = Seam.page(context, cards: cards)

        #expect(page.protocolOptions.map(\.name) == ["Able", "Beta", "Same", "Same"])
        #expect(page.protocolOptions.map(\.filter) == [.specific("p-alpha"), .specific("p-beta"), .specific("p-1"), .specific("p-2")])
        #expect(page.protocolOptions.map(\.total) == [100, 100, 100, 100])
    }

    /// S6, U4: rows are signed contributions; a reward shows its own value as not counted; an
    /// unpriced row (BAD's implausible price) and an ignored one (SCAM) show no value; no row is
    /// ever hidden, dust (DAI, TINY, the USDT borrow) included.
    @Test func `token rows follow their row state`() {
        let page = Seam.page()
        let value = { (state: TokenRowState, value: Decimal?) in Seam.RowValue(state: state, value: value) }
        let expected: [UUID: Seam.RowValue] = [
            Fixture.tokenID(1): value(.counted, 1000),
            Fixture.tokenID(2): value(.counted, 6000),
            Fixture.tokenID(3): value(.counted, 10),
            Fixture.tokenID(4): value(.counted, Fixture.decimal("0.5")),
            Fixture.tokenID(5): value(.counted, 100),
            Fixture.tokenID(6): value(.counted, 160),
            Fixture.tokenID(7): value(.counted, 70),
            Fixture.tokenID(8): value(.unpriced, nil),
            Fixture.tokenID(9): value(.counted, Fixture.decimal("0.3")),
            Fixture.tokenID(10): value(.counted, 100),
            Fixture.tokenID(11): value(.counted, 250),
            Fixture.tokenID(12): value(.counted, 3000),
            Fixture.tokenID(13): value(.counted, -1500),
            Fixture.tokenID(14): value(.counted, Fixture.decimal("-0.4")),
            Fixture.tokenID(15): value(.counted, 1500),
            Fixture.tokenID(16): value(.notCounted, 150),
            Fixture.tokenID(17): value(.counted, 90),
            Fixture.tokenID(18): value(.ignored, nil)
        ]

        #expect(Set(Seam.rows(page).keys) == Set(Fixture.inputs.map(\.tokenId)))
        #expect(Seam.rows(page) == expected)
    }

    /// From the retired PositionGroupValue test: supply 2 and borrow 1 ETH at live 3100, plus a
    /// 10 ETH reward, make a $3,100 card. The reward row shows its own $31,000, not counted, and a
    /// zero-amount token is a not-counted row worth 0.
    @Test func `a card leaves out rewards and subtracts borrows`() {
        let eth = { (role: TokenRole, amount: Decimal, usdValue: Decimal) in
            Fixture.token(Fixture.AssetID.eth, "ETH", "Ethereum", .major, coinGeckoId: "ethereum", role: role, amount: amount, usdValue: usdValue)
        }
        let context = Fixture.context(
            tokens: [eth(.supply, 2, 6000), eth(.borrow, 1, 3000), eth(.reward, 10, 500), eth(.supply, 0, 0)],
            livePricesUSD: ["ethereum": 3100])

        let page = Seam.page(context, cards: [Seam.card(.wallet)])
        let rows = page.sections.flatMap(\.cards).flatMap(\.rows).map { Seam.RowValue(state: $0.state, value: $0.value) }

        #expect(Seam.cardTotals(page) == [Fixture.PositionID.wallet: 3100])
        #expect(rows == [
            Seam.RowValue(state: .counted, value: 6200),
            Seam.RowValue(state: .counted, value: -3100),
            Seam.RowValue(state: .notCounted, value: 31000),
            Seam.RowValue(state: .notCounted, value: 0)
        ])
    }

    /// The display rate is applied once, to the module's USD results: at 0.5 every figure halves.
    @Test func `the display rate is applied once`() {
        let page = Seam.page(Fixture.context(rate: Fixture.decimal("0.5")))

        #expect(page.typeOptions.first?.total == Fixture.decimal("5390.2"))
        #expect(Seam.cardTotals(page)[Fixture.PositionID.aave] == Fixture.decimal("749.8"))
        #expect(page.sections.map(\.total) == [Fixture.decimal("3845.4"), Fixture.decimal("749.8"), 750, 45])
        #expect(Seam.rows(page)[Fixture.tokenID(13)] == Seam.RowValue(state: .counted, value: -750))
        #expect(Seam.rows(page)[Fixture.tokenID(16)] == Seam.RowValue(state: .notCounted, value: 75))
    }
}
