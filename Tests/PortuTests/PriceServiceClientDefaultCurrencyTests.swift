import Foundation
@testable import Portu
import PortuCore
import Testing

struct PriceServiceClientDefaultCurrencyTests {
    @Test func `default coin gecko getter returns the usd update for the default currency`() async throws {
        let client = makeClient()
        let request = PricePollingRequest(coinGeckoIDs: ["btc"], zapperIdentities: [])

        let update = try await client.fetchCoinGeckoPrices(request, .default, 1)

        #expect(update.currency == .usd)
        #expect(update.prices["btc"] == 100)
    }

    @Test func `default coin gecko getter returns an empty tagged update for a non-default currency`() async throws {
        let client = makeClient()
        let request = PricePollingRequest(coinGeckoIDs: ["btc"], zapperIdentities: [])

        let update = try await client.fetchCoinGeckoPrices(request, .eur, 1)

        #expect(update.currency == .eur)
        #expect(update.prices.isEmpty)
    }

    @Test func `default zapper getter returns an empty tagged update for a non-default currency`() async throws {
        let client = makeClient()
        let identity = try #require(OnchainTokenIdentity(historicalPriceID: "asset:base:0xtoken"))

        let update = try await client.fetchZapperPrices([identity], .chf, 1)

        #expect(update.currency == .chf)
        #expect(update.prices.isEmpty)
    }

    @Test func `default historical prices for currency getter delegates to usd fetch for the default currency`() async throws {
        let client = makeClient()

        let rows = try await client.fetchHistoricalPricesForCurrency("btc", .default, 7)

        #expect(rows.map(\.coinGeckoId) == ["btc"])
    }

    @Test func `default historical prices for currency getter returns empty rows for a non-default currency`() async throws {
        let client = makeClient()

        let rows = try await client.fetchHistoricalPricesForCurrency("btc", .eur, 7)

        #expect(rows.isEmpty)
    }

    private func makeClient() -> PriceServiceClient {
        PriceServiceClient(
            fetchPrices: { _ in PriceUpdate(prices: ["btc": 100], changes24h: [:]) },
            fetchHistoricalPrices: { coinId, _ in [HistoricalPriceDTO(coinGeckoId: coinId, timestamp: .now, usdPrice: 100)] },
            invalidateCache: {})
    }
}
