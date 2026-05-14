import Foundation
import PortuCore

struct TokenIdentityMappingSnapshot: Equatable, Identifiable {
    var id: UUID
    var canonicalKey: String
    var chain: Chain
    var contractAddress: String
    var coinGeckoId: String?
    var zapperId: String?

    init(
        id: UUID = UUID(),
        identity: OnchainTokenIdentity,
        coinGeckoId: String? = nil,
        zapperId: String? = nil) {
        self.id = id
        self.canonicalKey = TokenIdentityMapping.canonicalKey(for: identity)
        self.chain = identity.chain
        self.contractAddress = identity.contractAddress
        self.coinGeckoId = TokenIdentityMappingFeature.normalizedProviderID(coinGeckoId)
        self.zapperId = TokenIdentityMappingFeature.normalizedProviderID(zapperId)
    }

    @MainActor
    init(_ mapping: TokenIdentityMapping) {
        self.id = mapping.id
        self.canonicalKey = mapping.canonicalKey
        self.chain = mapping.chain
        self.contractAddress = mapping.contractAddress
        self.coinGeckoId = TokenIdentityMappingFeature.normalizedProviderID(mapping.coinGeckoId)
        self.zapperId = TokenIdentityMappingFeature.normalizedProviderID(mapping.zapperId)
    }

    var onchainIdentity: OnchainTokenIdentity {
        OnchainTokenIdentity(chain: chain, contractAddress: contractAddress)
    }
}

enum TokenIdentityMappingFeature {
    static func mappingsByIdentity(
        _ mappings: [TokenIdentityMappingSnapshot]) -> [OnchainTokenIdentity: TokenIdentityMappingSnapshot] {
        var result: [OnchainTokenIdentity: TokenIdentityMappingSnapshot] = [:]
        for mapping in mappings {
            let identity = mapping.onchainIdentity
            if let existing = result[identity] {
                result[identity] = preferred(mapping, over: existing)
            } else {
                result[identity] = mapping
            }
        }
        return result
    }

    static func mappedCoinGeckoID(
        for identity: OnchainTokenIdentity?,
        mappingsByIdentity mappings: [OnchainTokenIdentity: TokenIdentityMappingSnapshot]) -> String? {
        guard let identity else { return nil }
        return normalizedProviderID(mappings[identity]?.coinGeckoId)
    }

    static func priceID(
        coinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity?) -> String? {
        normalizedProviderID(coinGeckoId) ?? onchainIdentity?.historicalPriceID
    }

    static func nonZapperPriceID(_ id: String?) -> String? {
        guard let id = normalizedProviderID(id), OnchainTokenIdentity(historicalPriceID: id) == nil else {
            return nil
        }
        return id
    }

    static func normalizedProviderID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func preferred(
        _ candidate: TokenIdentityMappingSnapshot,
        over existing: TokenIdentityMappingSnapshot) -> TokenIdentityMappingSnapshot {
        if existing.coinGeckoId == nil, candidate.coinGeckoId != nil {
            return candidate
        }
        if existing.zapperId == nil, candidate.zapperId != nil {
            return candidate
        }
        return candidate.id.uuidString < existing.id.uuidString ? candidate : existing
    }
}
