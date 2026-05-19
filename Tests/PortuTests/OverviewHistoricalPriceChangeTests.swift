import Foundation
@testable import Portu
import PortuCore
import Testing

struct OverviewHistoricalPriceChangeTests {
    @Test func `price display does not round tiny positive prices to zero`() throws {
        let price = try OverviewPriceDisplay.price(#require(Decimal(
            string: "0.0000000045",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(price == "$ <0.00000001")
    }

    @Test func `compact price display keeps constrained rows readable`() throws {
        let price = try OverviewPriceDisplay.compactPrice(#require(Decimal(
            string: "0.0000000045",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(price == "$ <1e-8")
    }

    @Test func `historical price cache derives latest daily price changes`() {
        let id = "asset:base:0xabc"
        let oldDay = Date(timeIntervalSince1970: 0)
        let previousDay = Date(timeIntervalSince1970: 86400)
        let latestDay = Date(timeIntervalSince1970: 172_800)

        let changes = OverviewHistoricalPriceChangeFeature.changes24h(from: [
            HistoricalPriceEntry(coinGeckoId: id, day: oldDay, usdPrice: 1),
            HistoricalPriceEntry(coinGeckoId: id, day: previousDay, usdPrice: 2),
            HistoricalPriceEntry(coinGeckoId: id, day: latestDay, usdPrice: 3),
            HistoricalPriceEntry(coinGeckoId: "ignored", day: latestDay, usdPrice: 1)
        ])

        #expect(changes[id] == 0.5)
        #expect(changes["ignored"] == nil)
    }

    @Test func `historical price cache normalizes legacy zapper ids to canonical asset ids`() {
        let previousDay = Date(timeIntervalSince1970: 86400)
        let latestDay = Date(timeIntervalSince1970: 172_800)
        let canonicalID = "asset:base:0xabc"

        let changes = OverviewHistoricalPriceChangeFeature.changes24h(from: [
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: previousDay, usdPrice: 2),
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: latestDay, usdPrice: 3)
        ])

        #expect(changes[canonicalID] == 0.5)
        #expect(changes["zapper:base:0xabc"] == nil)
    }

    @Test func `latest historical prices prefer newest row and canonicalize onchain ids`() {
        let oldDay = Date(timeIntervalSince1970: 0)
        let latestDay = Date(timeIntervalSince1970: 172_800)

        let prices = OverviewHistoricalPriceChangeFeature.latestPrices(from: [
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: oldDay, usdPrice: 1),
            HistoricalPriceEntry(coinGeckoId: "zapper:base:0xabc", day: latestDay, usdPrice: 3),
            HistoricalPriceEntry(coinGeckoId: "bitcoin", day: latestDay, usdPrice: 100)
        ])

        #expect(prices["asset:base:0xabc"] == 3)
        #expect(prices["zapper:base:0xabc"] == nil)
        #expect(prices["bitcoin"] == 100)
    }

    @Test func `merged price cache lets live prices override historical fallback`() {
        let merged = OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: ["ethereum": 2200],
            historical: ["ethereum": 2100, "asset:base:0xabc": 3])

        #expect(merged["ethereum"] == 2200)
        #expect(merged["asset:base:0xabc"] == 3)
    }

    @Test func `historical price change query starts at utc day two days before now`() {
        let now = Date(timeIntervalSince1970: 172_800 + 43200)

        let startDate = OverviewHistoricalPriceChangeFeature.queryStartDate(now: now)

        #expect(startDate == Date(timeIntervalSince1970: 0))
    }

    @Test func `historical price changes backfill overview key changes when live changes are missing`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xZapper")
        let token = token(symbol: "ZAP", amount: 3, usdValue: 15, onchainIdentity: identity)
        let changes24h = OverviewHistoricalPriceChangeFeature.mergedChanges24h(
            live: [:],
            historical: [identity.historicalPriceID: -0.20])

        let changes = OverviewPriceChangeFeature.keyChangeTokens(
            tokens: [token],
            prices: [:],
            changes24h: changes24h,
            overrides: [],
            mappings: [])

        #expect(changes.map(\.token.symbol) == ["ZAP"])
        #expect(changes.map(\.change) == [-3])
    }

    @Test func `portfolio change can ignore dashboard dust outliers`() {
        let dustIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xDust")
        let visibleIdentity = OnchainTokenIdentity(chain: .base, contractAddress: "0xVisible")
        let dust = token(symbol: "DUST", amount: 1, usdValue: 0.25, onchainIdentity: dustIdentity)
        let visible = token(symbol: "VISIBLE", amount: 2, usdValue: 10, onchainIdentity: visibleIdentity)

        let change = OverviewPriceChangeFeature.portfolioChange24h(
            tokens: [dust, visible],
            prices: [:],
            changes24h: [
                dustIdentity.historicalPriceID: 1_000_000_000,
                visibleIdentity.historicalPriceID: 0.10
            ],
            overrides: [],
            mappings: [],
            settings: .defaults)

        #expect(change == 1)
    }

    private func token(
        assetId: UUID = UUID(),
        symbol: String,
        category: AssetCategory = .major,
        coinGeckoId: String? = nil,
        role: TokenRole = .balance,
        amount: Decimal,
        usdValue: Decimal,
        onchainIdentity: OnchainTokenIdentity? = nil) -> TokenEntry {
        TokenEntry(
            assetId: assetId,
            symbol: symbol,
            name: symbol,
            category: category,
            coinGeckoId: coinGeckoId,
            onchainIdentity: onchainIdentity,
            role: role,
            amount: amount,
            usdValue: usdValue)
    }
}
