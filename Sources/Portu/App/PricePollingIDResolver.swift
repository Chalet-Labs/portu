import Foundation
import PortuCore

struct PricePollingRequest: Equatable {
    var coinGeckoIDs: [String]
    var onchainIdentities: [OnchainTokenIdentity]

    var isEmpty: Bool {
        coinGeckoIDs.isEmpty && onchainIdentities.isEmpty
    }

    var allPriceIDs: [String] {
        coinGeckoIDs + onchainIdentities.map(\.historicalPriceID)
    }
}

enum PricePollingIDResolver {
    static func split(_ ids: [String]) -> PricePollingRequest {
        var coinGeckoIDs: [String] = []
        var seenCoinGeckoIDs: Set<String> = []
        var onchainIdentities: [OnchainTokenIdentity] = []
        var seenOnchainIdentities: Set<OnchainTokenIdentity> = []

        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let identity = OnchainTokenIdentity(historicalPriceID: trimmed) {
                guard !seenOnchainIdentities.contains(identity) else { continue }
                seenOnchainIdentities.insert(identity)
                onchainIdentities.append(identity)
            } else {
                let normalized = trimmed.lowercased()
                guard !seenCoinGeckoIDs.contains(normalized) else { continue }
                seenCoinGeckoIDs.insert(normalized)
                coinGeckoIDs.append(normalized)
            }
        }

        return PricePollingRequest(
            coinGeckoIDs: coinGeckoIDs,
            onchainIdentities: onchainIdentities)
    }

    static func merge(_ updates: [PriceUpdate]) -> PriceUpdate {
        var prices: [String: Decimal] = [:]
        var changes24h: [String: Decimal] = [:]
        let currency = updates.first?.currency ?? .default

        for update in updates {
            prices.merge(update.prices) { _, new in new }
            changes24h.merge(update.changes24h) { _, new in new }
        }

        return PriceUpdate(currency: currency, prices: prices, changes24h: changes24h)
    }

    static var emptyUpdate: PriceUpdate {
        emptyUpdate(currency: .default)
    }

    static func emptyUpdate(currency: FiatCurrency) -> PriceUpdate {
        PriceUpdate(currency: currency, prices: [:], changes24h: [:])
    }
}
