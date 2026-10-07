import Foundation
import PortuCore
import PortuNetwork

/// Builds USD price updates for live polling. Nothing here converts to the display
/// currency; the rate is applied where prices are shown.
enum LivePriceUpdateBuilder {
    static func fetchPrices(
        coinIds: [String],
        priceService: PriceService,
        fetchOnchainFallbackUpdate: @escaping @Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate) async throws -> PriceUpdate {
        let request = PricePollingIDResolver.split(coinIds)
        let coinGeckoUpdate = try await fetchCoinGeckoIDUpdate(
            coinIDs: request.coinGeckoIDs,
            priceService: priceService,
            allowEmptyOnFailure: !request.onchainIdentities.isEmpty)
        let tokenUpdate = await fetchCoinGeckoTokenUpdate(
            identities: request.onchainIdentities,
            priceService: priceService)
        let unresolvedOnchainIdentities = request.onchainIdentities.filter {
            tokenUpdate.prices[$0.historicalPriceID] == nil
        }
        let onchainFallbackUpdate: PriceUpdate
        do {
            onchainFallbackUpdate = try await fetchOnchainFallbackUpdate(unresolvedOnchainIdentities)
        } catch {
            onchainFallbackUpdate = PricePollingIDResolver.emptyUpdate
        }
        return PricePollingIDResolver.merge([coinGeckoUpdate, tokenUpdate, onchainFallbackUpdate])
    }

    static func fetchCoinGeckoPrices(
        request: PricePollingRequest,
        priceService: PriceService) async throws -> PriceUpdate {
        let coinGeckoUpdate = try await fetchCoinGeckoIDUpdate(
            coinIDs: request.coinGeckoIDs,
            priceService: priceService,
            allowEmptyOnFailure: !request.onchainIdentities.isEmpty)
        let tokenUpdate = await fetchCoinGeckoTokenUpdate(
            identities: request.onchainIdentities,
            priceService: priceService)
        return PricePollingIDResolver.merge([coinGeckoUpdate, tokenUpdate])
    }

    private static func fetchCoinGeckoIDUpdate(
        coinIDs: [String],
        priceService: PriceService,
        allowEmptyOnFailure: Bool) async throws -> PriceUpdate {
        guard !coinIDs.isEmpty else { return PricePollingIDResolver.emptyUpdate }
        do {
            return try await priceService.fetchPriceUpdate(for: coinIDs)
        } catch {
            guard allowEmptyOnFailure else { throw error }
            return PricePollingIDResolver.emptyUpdate
        }
    }

    private static func fetchCoinGeckoTokenUpdate(
        identities: [OnchainTokenIdentity],
        priceService: PriceService) async -> PriceUpdate {
        guard !identities.isEmpty else { return PricePollingIDResolver.emptyUpdate }
        do {
            return try await priceService.fetchTokenPriceUpdate(for: identities)
        } catch {
            return PricePollingIDResolver.emptyUpdate
        }
    }
}
