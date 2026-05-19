import Foundation
import PortuCore

struct PricePollingRequest: Equatable {
    var coinGeckoIDs: [String]
    var zapperIdentities: [OnchainTokenIdentity]
}

enum PricePollingIDResolver {
    static func split(_ ids: [String]) -> PricePollingRequest {
        var coinGeckoIDs: [String] = []
        var seenCoinGeckoIDs: Set<String> = []
        var zapperIdentities: [OnchainTokenIdentity] = []
        var seenZapperIdentities: Set<OnchainTokenIdentity> = []

        for id in ids {
            let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if let identity = OnchainTokenIdentity(historicalPriceID: normalized) {
                guard !seenZapperIdentities.contains(identity) else { continue }
                seenZapperIdentities.insert(identity)
                zapperIdentities.append(identity)
            } else {
                guard !seenCoinGeckoIDs.contains(normalized) else { continue }
                seenCoinGeckoIDs.insert(normalized)
                coinGeckoIDs.append(normalized)
            }
        }

        return PricePollingRequest(
            coinGeckoIDs: coinGeckoIDs,
            zapperIdentities: zapperIdentities)
    }

    static func merge(_ updates: [PriceUpdate]) -> PriceUpdate {
        var prices: [String: Decimal] = [:]
        var changes24h: [String: Decimal] = [:]

        for update in updates {
            prices.merge(update.prices) { _, new in new }
            changes24h.merge(update.changes24h) { _, new in new }
        }

        return PriceUpdate(prices: prices, changes24h: changes24h)
    }

    static var emptyUpdate: PriceUpdate {
        PriceUpdate(prices: [:], changes24h: [:])
    }
}
