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

    @Test func `merged historical price entries pick the row with the latest fetchedAt on duplicate days`() {
        let day = Date(timeIntervalSince1970: 1_704_067_200)
        let olderFetch = day
        let newerFetch = day.addingTimeInterval(3600)

        let freshRow = HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day,
            currency: .usd,
            price: 41000,
            fetchedAt: newerFetch)
        let staleRow = HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: day,
            currency: .usd,
            price: 40000,
            fetchedAt: olderFetch)

        let entries = OverviewHistoricalPriceChangeFeature.mergedHistoricalPriceEntries(
            from: [freshRow, staleRow],
            displayCurrency: .usd,
            context: .usd)

        #expect(entries.map(\.usdPrice) == [41000])
    }

    @Test func `merged historical price entries normalize day to utc start of day`() {
        let midday = Date(timeIntervalSince1970: 1_704_067_200 + 12 * 3600)
        let normalizedDay = HistoricalPriceCalendar.utcStartOfDay(for: midday)

        let usdRow = HistoricalPricePoint(
            coinGeckoId: "bitcoin",
            day: midday,
            currency: .usd,
            price: 41000,
            fetchedAt: midday)
        let displayCurrencyRow = HistoricalPricePoint(
            coinGeckoId: "ethereum",
            day: midday,
            currency: .eur,
            price: 2000,
            fetchedAt: midday)

        let entries = OverviewHistoricalPriceChangeFeature.mergedHistoricalPriceEntries(
            from: [usdRow, displayCurrencyRow],
            displayCurrency: .eur,
            context: .usd)

        #expect(entries.allSatisfy { $0.day == normalizedDay })
    }

    @Test func `merged price cache lets live prices override historical fallback`() {
        let merged = OverviewHistoricalPriceChangeFeature.mergedPrices(
            live: ["ethereum": 2200],
            historical: ["ethereum": 2100, "asset:base:0xabc": 3])

        #expect(merged["ethereum"] == 2200)
        #expect(merged["asset:base:0xabc"] == 3)
    }

    /// No live price or change: the token is valued from its sync value and moved by the historical
    /// fraction. Exact formula (V4): 15 × −0.2 / 0.8 = −3.75.
    @Test func `historical price changes backfill overview key changes when live changes are missing`() {
        let identity = OnchainTokenIdentity(chain: .base, contractAddress: "0xProvider")
        let context = PortfolioValuationFixture.context(
            tokens: [token(symbol: "ZAP", amount: 3, usdValue: 15, onchainIdentity: identity)],
            historical: HistoricalMarketPrices(changes24h: [identity.historicalPriceID: PortfolioValuationFixture.decimal("-0.2")]))

        let rows = OverviewPositionProjection.tab(.keyChanges, context: context, positions: PortfolioValuationFixture.positions)
            .groups.flatMap(\.tokens)

        #expect(rows.map(\.symbol) == ["ZAP"])
        #expect(rows.map(\.change24h) == [PortfolioValuationFixture.decimal("-3.75")])
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
