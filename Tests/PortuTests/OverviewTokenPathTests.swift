import Foundation
@testable import Portu
import PortuCore
import Testing

/// T2: one token, the same value on every Overview path. A token's share of the headline and of
/// the cards is the change when the fixture is valued without its asset; the lists show it as a row.
struct OverviewTokenPathTests {
    private typealias Fixture = OverviewValuationFixture

    @Test func `a sync only token counts its sync value on every path`() {
        #expect(headlineShare(of: Fixture.AssetID.otc) == 250)
        #expect(cardsShare(of: Fixture.AssetID.otc) == 250)
        #expect(slice("OTC", .assets) == 250)
        #expect(weight("OTC") == 250)
        #expect(watchlistPrice("OTC") == 50)
    }

    @Test func `a close on the sync day loses to the sync value on every path`() {
        #expect(headlineShare(of: Fixture.AssetID.uni) == 70)
        #expect(cardsShare(of: Fixture.AssetID.uni) == 70)
        #expect(slice("DeFi", .category) == 330)
        #expect(weight("UNI") == 70)
        #expect(watchlistPrice("UNI") == 7)
    }

    @Test func `a close on a later day than the sync wins on every path`() {
        #expect(headlineShare(of: Fixture.AssetID.link) == 160)
        #expect(cardsShare(of: Fixture.AssetID.link) == 160)
        #expect(slice("LINK", .assets) == 160)
        #expect(weight("LINK") == 160)
        #expect(watchlistPrice("LINK") == 16)
    }

    @Test func `a manual price wins on every path`() {
        #expect(headlineShare(of: Fixture.AssetID.manual) == 100)
        #expect(cardsShare(of: Fixture.AssetID.manual) == 100)
        #expect(weight("MNL") == 100)
        #expect(watchlistPrice("MNL") == 2)
    }

    @Test func `a mapped onchain token is priced through its mapping on every path`() {
        #expect(headlineShare(of: Fixture.AssetID.degen) == 100)
        #expect(slice("Meme", .category) == 110)
        #expect(watchlistPrice("DEGEN") == Fixture.decimal("0.01"))
        #expect(cardsShare(of: Fixture.AssetID.degen) == 100)
        #expect(weight("DEGEN") == 100)
    }

    @Test func `an implausible onchain live price is unpriced on every path`() {
        #expect(headlineShare(of: Fixture.AssetID.bad) == 0)
        #expect(cardsShare(of: Fixture.AssetID.bad) == 0)
        #expect(slice("BAD", .assets) == nil)
        #expect(weight("BAD") == nil)
        #expect(watchlistPrice("BAD") == nil)
    }

    @Test func `an ignored token is absent from every path`() {
        #expect(headlineShare(of: Fixture.AssetID.scam) == 0)
        #expect(cardsShare(of: Fixture.AssetID.scam) == 0)
        #expect(slice("SCAM", .assets) == nil)
        #expect(weight("SCAM") == nil)
        #expect(watchlistPrice("SCAM") == nil)
    }

    @Test func `dust counts in totals while the lists hide it`() {
        let idleStables = OverviewPositionProjection.tab(.idleStables, context: Fixture.context(), positions: Fixture.positions)
        #expect(!idleStables.groups.flatMap(\.tokens).contains { $0.symbol == "DAI" })
        #expect(weight("DAI") == nil)
        #expect(headlineShare(of: Fixture.AssetID.dai) == Fixture.decimal("0.5"))
        #expect(cardsShare(of: Fixture.AssetID.dai) == Fixture.decimal("0.5"))
        #expect(headlineShare(of: Fixture.AssetID.usdt) == Fixture.decimal("-0.4"))
        #expect(cardsShare(of: Fixture.AssetID.usdt) == Fixture.decimal("-0.4"))
    }

    @Test func `an always shown dust token keeps its value on every path`() {
        #expect(headlineShare(of: Fixture.AssetID.tiny) == Fixture.decimal("0.3"))
        #expect(cardsShare(of: Fixture.AssetID.tiny) == Fixture.decimal("0.3"))
        #expect(weight("TINY") == Fixture.decimal("0.3"))
    }

    @Test func `a reward counts nothing on any path`() {
        let withoutReward = Fixture.inputs.filter { $0.tokenId != Fixture.tokenID(16) }

        #expect(OverviewFeature.headline(Fixture.context(inputs: withoutReward)) == OverviewFeature.headline(Fixture.context()))
        #expect(cardsNet(Fixture.context(inputs: withoutReward)) == cardsNet(Fixture.context()))
        #expect(weight("SOL") == 1500)
    }

    // MARK: - Paths

    private func headlineShare(of asset: UUID) -> Decimal {
        OverviewFeature.headline(Fixture.context()).total
            - OverviewFeature.headline(Fixture.context(excluding: [asset])).total
    }

    private func cardsShare(of asset: UUID) -> Decimal {
        cardsNet(Fixture.context()) - cardsNet(Fixture.context(excluding: [asset]))
    }

    /// Idle + Deployed − Debt.
    private func cardsNet(_ context: OverviewValuationContext) -> Decimal {
        OverviewSummaryCardsFeature.cards(context, categories: PortfolioCategoryDefaults.categorySnapshots)
            .reduce(Decimal.zero) { total, card in
                let sum = card.rows.reduce(Decimal.zero) { $0 + $1.value }
                return card.title == "Debt" ? total - sum : total + sum
            }
    }

    private func slice(_ label: String, _ mode: TopAssetMode) -> Decimal? {
        OverviewFeature.topAssets(mode, context: Fixture.context()).slices.first { $0.label == label }?.value
    }

    private func weight(_ symbol: String) -> Decimal? {
        PortfolioHealthFeature.health(Fixture.context())
            .weights.first { $0.symbol == symbol }?.usdValue
    }

    private func watchlistPrice(_ symbol: String) -> Decimal? {
        OverviewFeature.watchlistRows(Fixture.context(), assets: [], watchlistIDs: [])
            .first { $0.symbol == symbol }?.price
    }
}
