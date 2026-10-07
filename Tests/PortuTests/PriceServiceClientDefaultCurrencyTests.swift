import Foundation
@testable import Portu
import PortuCore
import Synchronization
import Testing

struct PriceServiceClientDefaultCurrencyTests {
    @Test func `default coin gecko getter fetches every polling id in usd`() async throws {
        let requested = Mutex<[[String]]>([])
        let client = makeClient { ids in requested.withLock { $0.append(ids) } }
        let identity = try #require(OnchainTokenIdentity(historicalPriceID: "asset:base:0xtoken"))
        let request = PricePollingRequest(coinGeckoIDs: ["btc"], onchainIdentities: [identity])

        let update = try await client.fetchCoinGeckoPrices(request)

        #expect(update.currency == .usd)
        #expect(update.prices["btc"] == 100)
        #expect(requested.withLock { $0 } == [["btc", identity.historicalPriceID]])
    }

    @Test func `default onchain fallback getter fetches the identity price ids in usd`() async throws {
        let requested = Mutex<[[String]]>([])
        let client = makeClient { ids in requested.withLock { $0.append(ids) } }
        let identity = try #require(OnchainTokenIdentity(historicalPriceID: "asset:base:0xtoken"))

        let update = try await client.fetchOnchainFallbackPrices([identity])

        #expect(update.currency == .usd)
        #expect(update.prices["btc"] == 100)
        #expect(requested.withLock { $0 } == [[identity.historicalPriceID]])
    }

    @Test func `overridden getters replace the defaults`() async throws {
        let client = {
            var client = makeClient()
            client.fetchCoinGeckoPrices = { _ in PriceUpdate(prices: ["eth": 5], changes24h: [:]) }
            client.fetchOnchainFallbackPrices = { _ in PriceUpdate(prices: ["asset:base:0xtoken": 7], changes24h: [:]) }
            return client
        }()
        let identity = try #require(OnchainTokenIdentity(historicalPriceID: "asset:base:0xtoken"))

        let coinGecko = try await client.fetchCoinGeckoPrices(PricePollingRequest(coinGeckoIDs: ["eth"], onchainIdentities: []))
        let onchain = try await client.fetchOnchainFallbackPrices([identity])

        #expect(coinGecko.prices == ["eth": 5])
        #expect(onchain.prices == ["asset:base:0xtoken": 7])
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

    private func makeClient(onFetch: @escaping @Sendable ([String]) -> Void = { _ in }) -> PriceServiceClient {
        PriceServiceClient(
            fetchPrices: { ids in
                onFetch(ids)
                return PriceUpdate(prices: ["btc": 100], changes24h: [:])
            },
            fetchHistoricalPrices: { coinId, _ in [HistoricalPriceDTO(coinGeckoId: coinId, timestamp: .now, usdPrice: 100)] },
            invalidateCache: {})
    }
}
