import Foundation
@testable import Portu
import PortuCore
import SwiftData
import SwiftUI
import Testing

/// The active portfolio model boundary over an in-memory store, through the All Positions page seam.
@MainActor
struct ActivePortfolioProjectionTests {
    private static let syncedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Spec Terms (AGENT-DECIDED 23): a token whose asset is gone is outside valuation, so it has no
    /// row and adds nothing. An active position with no token keeps its $0 card; an inactive
    /// account's position has none.
    @Test func `the projection covers active positions and drops asset-less tokens`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        let active = Account(name: "Main Wallet", kind: .wallet, dataSource: .zerion)
        let archived = Account(name: "Archived Wallet", kind: .wallet, dataSource: .zerion, isActive: false)
        let holding = Position(
            positionType: .idle,
            chain: .ethereum,
            netUSDValue: 6040,
            tokens: [
                PositionToken(role: .balance, amount: 2, usdValue: 6000, asset: eth),
                PositionToken(role: .balance, amount: 4, usdValue: 40)
            ],
            account: active,
            syncedAt: Self.syncedAt)
        let empty = Position(positionType: .lending, protocolId: "aave-v3", protocolName: "Aave V3", account: active, syncedAt: Self.syncedAt)
        let offline = Position(
            positionType: .idle,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: 50, asset: eth)],
            account: archived,
            syncedAt: Self.syncedAt)
        context.insert(eth)
        context.insert(active)
        context.insert(archived)
        for position in [holding, empty, offline] {
            context.insert(position)
        }
        try context.save()

        let projection = try ActivePortfolioProjection(context.fetch(FetchDescriptor<Position>()))
        let page = AllPositionsFeature.page(Self.context(projection.inputs), cards: projection.cards, filter: .all)
        let cards = page.sections.flatMap(\.cards)

        #expect(Set(projection.cards.map(\.id)) == [holding.id, empty.id])
        #expect(projection.inputs.map(\.token.symbol) == ["ETH"])
        #expect(cards.first { $0.id == holding.id }?.rows.map(\.symbol) == ["ETH"])
        #expect(cards.first { $0.id == empty.id }?.rows.isEmpty == true)
        #expect(cards.first { $0.id == empty.id }?.total == 0)
        #expect(page.sections.first { $0.type == .lending }?.total == 0)
        #expect(page.typeOptions.first?.total == 6000)
    }

    /// Plan, All Positions number changes: a manual position's section follows live price × amount
    /// (V1), not the USD value stored when it was entered.
    @Test func `a manual position follows the live price, not its stored value`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let eth = Asset(symbol: "ETH", name: "Ethereum", coinGeckoId: "ethereum", category: .major)
        let manual = Account(name: "Cold Storage", kind: .manual, dataSource: .manual)
        let position = Position(
            positionType: .idle,
            protocolName: "Ledger",
            netUSDValue: 500,
            tokens: [PositionToken(role: .balance, amount: 1, usdValue: 500, asset: eth)],
            account: manual,
            syncedAt: Self.syncedAt)
        context.insert(eth)
        context.insert(manual)
        context.insert(position)
        try context.save()

        let projection = try ActivePortfolioProjection(context.fetch(FetchDescriptor<Position>()))
        let page = AllPositionsFeature.page(
            Self.context(projection.inputs, livePricesUSD: ["ethereum": 3050]),
            cards: projection.cards,
            filter: .all)

        #expect(page.sections.map(\.type) == [.idle])
        #expect(page.sections.map(\.total) == [3050])
        #expect(page.sections.flatMap(\.cards).map(\.total) == [3050])
        #expect(page.sections.flatMap(\.cards).flatMap(\.rows).map(\.value) == [3050])
        #expect(page.protocolOptions.map(\.total) == [3050])
    }

    /// #103: a sync deletes the positions a projection came from while a view may still hold it.
    /// Everything it hands on stays readable and renderable.
    @Test func `the projection outlives deletion of its source models`() throws {
        let container = try ModelContainerFactory().makeInMemory()
        let context = container.mainContext
        let usdc = Asset(symbol: "USDC", name: "USD Coin", coinGeckoId: "usd-coin", category: .stablecoin)
        let wallet = Account(name: "Main Wallet", kind: .wallet, dataSource: .zerion)
        context.insert(usdc)
        context.insert(wallet)
        context.insert(Position(
            positionType: .lending,
            chain: .ethereum,
            protocolId: "aave-v3",
            protocolName: "Aave V3",
            healthFactor: 2.4,
            tokens: [
                PositionToken(role: .supply, amount: 4000, usdValue: 4000, asset: usdc),
                PositionToken(role: .borrow, amount: 500, usdValue: 500, asset: usdc)
            ],
            account: wallet,
            syncedAt: Self.syncedAt))
        try context.save()
        let positions = try context.fetch(FetchDescriptor<Position>())
        let projection = ActivePortfolioProjection(positions)

        for position in positions {
            context.delete(position)
        }
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Position>()).isEmpty)
        #expect(projection.inputs.map(\.token.symbol) == ["USDC", "USDC"])
        #expect(projection.cards.map(\.protocolName) == ["Aave V3"])
        let page = AllPositionsFeature.page(
            Self.context(projection.inputs, livePricesUSD: ["usd-coin": 1]),
            cards: projection.cards,
            filter: .all)
        let card = try #require(page.sections.first?.cards.first)
        #expect(card.title == "Aave V3")
        #expect(card.total == 3500)
        #expect(card.rows.map(\.value) == [4000, -500])

        ViewRenderSmokeTests().render(PositionGroupView(card: card, currencyCode: "USD"), size: CGSize(width: 800, height: 300))
    }

    private static func context(_ inputs: [ValuationInput], livePricesUSD: [String: Decimal] = [:]) -> ValuationContext {
        ValuationContext(
            inputs: inputs,
            overrides: [],
            mappings: [],
            settings: .showAll,
            usdToDisplayRate: 1,
            prices: ValuationPriceInputs(livePricesUSD: livePricesUSD))
    }
}
