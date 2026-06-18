import Foundation
import PortuCore
import PortuNetwork

enum LivePriceUpdateBuilder {
    static func fetchPrices(
        coinIds: [String],
        priceService: PriceService,
        fetchZapperUpdate: @escaping @Sendable ([OnchainTokenIdentity]) async throws -> PriceUpdate) async throws -> PriceUpdate {
        let request = PricePollingIDResolver.split(coinIds)
        let coinGeckoUpdate = try await fetchCoinGeckoIDUpdate(
            coinIDs: request.coinGeckoIDs,
            priceService: priceService,
            allowEmptyOnFailure: !request.zapperIdentities.isEmpty)
        let tokenUpdate = await fetchCoinGeckoTokenUpdate(
            identities: request.zapperIdentities,
            priceService: priceService)
        let unresolvedZapperIdentities = request.zapperIdentities.filter {
            tokenUpdate.prices[$0.historicalPriceID] == nil
        }
        let zapperUpdate: PriceUpdate
        do {
            zapperUpdate = try await fetchZapperUpdate(unresolvedZapperIdentities)
        } catch {
            zapperUpdate = PricePollingIDResolver.emptyUpdate
        }
        return PricePollingIDResolver.merge([coinGeckoUpdate, tokenUpdate, zapperUpdate])
    }

    static func fetchCoinGeckoPrices(
        request: PricePollingRequest,
        priceService: PriceService) async throws -> PriceUpdate {
        let coinGeckoUpdate = try await fetchCoinGeckoIDUpdate(
            coinIDs: request.coinGeckoIDs,
            priceService: priceService,
            allowEmptyOnFailure: !request.zapperIdentities.isEmpty)
        let tokenUpdate = await fetchCoinGeckoTokenUpdate(
            identities: request.zapperIdentities,
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
