import Foundation
import PortuCore

struct PricePollingRequest: Equatable {
    var coinGeckoIDs: [String]
    var zapperIdentities: [OnchainTokenIdentity]
}

enum PricePollingIDResolver {
    static func split(_ ids: [String]) -> PricePollingRequest {
        var coinGeckoIDs: Set<String> = []
        var zapperIdentities: Set<OnchainTokenIdentity> = []

        for id in ids {
            let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if let identity = OnchainTokenIdentity(historicalPriceID: normalized) {
                zapperIdentities.insert(identity)
            } else {
                coinGeckoIDs.insert(normalized)
            }
        }

        return PricePollingRequest(
            coinGeckoIDs: coinGeckoIDs.sorted(),
            zapperIdentities: zapperIdentities.sorted(by: sortIdentities))
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

    private static func sortIdentities(
        _ lhs: OnchainTokenIdentity,
        _ rhs: OnchainTokenIdentity) -> Bool {
        if lhs.chain.rawValue != rhs.chain.rawValue {
            return lhs.chain.rawValue < rhs.chain.rawValue
        }
        return lhs.contractAddress < rhs.contractAddress
    }
}
