import Foundation
import PortuCore
import PortuNetwork

enum LivePriceUpdateBuilder {
    static func fetchPrices(
        coinIds: [String],
        priceService: PriceService,
        currency: FiatCurrency = .default,
        fetchOnchainFallbackUpdate: @escaping @Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate) async throws -> PriceUpdate {
        let request = PricePollingIDResolver.split(coinIds)
        let coinGeckoUpdate = try await fetchCoinGeckoIDUpdate(
            coinIDs: request.coinGeckoIDs,
            priceService: priceService,
            currency: currency,
            allowEmptyOnFailure: !request.onchainIdentities.isEmpty)
        let tokenUpdate = await fetchCoinGeckoTokenUpdate(
            identities: request.onchainIdentities,
            priceService: priceService,
            currency: currency)
        let unresolvedOnchainIdentities = request.onchainIdentities.filter {
            tokenUpdate.prices[$0.historicalPriceID] == nil
        }
        let onchainFallbackUpdate: PriceUpdate
        do {
            let rawOnchainFallbackUpdate = try await fetchOnchainFallbackUpdate(unresolvedOnchainIdentities)
            if currency == .usd {
                onchainFallbackUpdate = rawOnchainFallbackUpdate
            } else {
                let rate = try await priceService.fetchCurrentUSDConversionRate(to: currency)
                onchainFallbackUpdate = rawOnchainFallbackUpdate.convertedUSDValues(to: currency, rate: rate)
            }
        } catch {
            onchainFallbackUpdate = PricePollingIDResolver.emptyUpdate(currency: currency)
        }
        return PricePollingIDResolver.merge([coinGeckoUpdate, tokenUpdate, onchainFallbackUpdate])
    }

    static func fetchCoinGeckoPrices(
        request: PricePollingRequest,
        priceService: PriceService,
        currency: FiatCurrency = .default) async throws -> PriceUpdate {
        let coinGeckoUpdate = try await fetchCoinGeckoIDUpdate(
            coinIDs: request.coinGeckoIDs,
            priceService: priceService,
            currency: currency,
            allowEmptyOnFailure: !request.onchainIdentities.isEmpty)
        let tokenUpdate = await fetchCoinGeckoTokenUpdate(
            identities: request.onchainIdentities,
            priceService: priceService,
            currency: currency)
        return PricePollingIDResolver.merge([coinGeckoUpdate, tokenUpdate])
    }

    private static func fetchCoinGeckoIDUpdate(
        coinIDs: [String],
        priceService: PriceService,
        currency: FiatCurrency,
        allowEmptyOnFailure: Bool) async throws -> PriceUpdate {
        guard !coinIDs.isEmpty else { return PricePollingIDResolver.emptyUpdate(currency: currency) }
        do {
            return try await priceService.fetchPriceUpdate(for: coinIDs, currency: currency)
        } catch {
            guard allowEmptyOnFailure else { throw error }
            return PricePollingIDResolver.emptyUpdate(currency: currency)
        }
    }

    private static func fetchCoinGeckoTokenUpdate(
        identities: [OnchainTokenIdentity],
        priceService: PriceService,
        currency: FiatCurrency) async -> PriceUpdate {
        guard !identities.isEmpty else { return PricePollingIDResolver.emptyUpdate(currency: currency) }
        do {
            return try await priceService.fetchTokenPriceUpdate(for: identities, currency: currency)
        } catch {
            return PricePollingIDResolver.emptyUpdate(currency: currency)
        }
    }
}
