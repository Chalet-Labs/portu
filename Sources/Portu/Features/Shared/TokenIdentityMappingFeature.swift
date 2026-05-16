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
    private static let nativeAssetAddress = "0x0000000000000000000000000000000000000000"

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
        if let nativeID = nativeCoinGeckoID(for: onchainIdentity) {
            return nativeID
        }
        if let onchainIdentity {
            return onchainIdentity.historicalPriceID
        }
        return normalizedProviderID(coinGeckoId)
    }

    static func nativeCoinGeckoID(for identity: OnchainTokenIdentity?) -> String? {
        guard
            let identity,
            identity.contractAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nativeAssetAddress
        else {
            return nil
        }

        switch identity.chain {
        case .ethereum, .arbitrum, .optimism, .base, .unichain, .zksync, .linea, .blast, .taiko, .scroll, .zora, .mode:
            return "ethereum"
        case .polygon, .bsc, .gnosis, .berachain, .sonic, .polygonZkEVM, .moonbeam, .ronin, .mantle, .immutableX,
             .hyperliquid, .solana, .bitcoin, .avalanche, .monad, .katana:
            return nil
        }
    }

    static func knownContractCoinGeckoID(for identity: OnchainTokenIdentity?) -> String? {
        guard let identity else { return nil }
        return knownContractCoinGeckoIDs[TokenIdentityMapping.canonicalKey(for: identity)]
    }

    static func nonZapperPriceID(_ id: String?) -> String? {
        guard let id = normalizedProviderID(id), OnchainTokenIdentity(historicalPriceID: id) == nil else {
            return nil
        }
        return id
    }

    static func normalizedHistoricalPriceID(_ id: String?) -> String? {
        guard let normalizedID = normalizedProviderID(id) else { return nil }
        if let identity = OnchainTokenIdentity(historicalPriceID: normalizedID) {
            return identity.historicalPriceID
        }
        return normalizedID
    }

    static func normalizedProviderID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static let knownContractCoinGeckoIDs: [String: String] = [
        TokenIdentityMapping.canonicalKey(
            chain: .ethereum,
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"): "usd-coin",
        TokenIdentityMapping.canonicalKey(
            chain: .arbitrum,
            contractAddress: "0xaf88d065e77c8cc2239327c5edb3a432268e5831"): "usd-coin",
        TokenIdentityMapping.canonicalKey(
            chain: .base,
            contractAddress: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"): "usd-coin",
        TokenIdentityMapping.canonicalKey(
            chain: .optimism,
            contractAddress: "0x0b2c639c533813f4aa9d7837caf62653d097ff85"): "usd-coin",
        TokenIdentityMapping.canonicalKey(
            chain: .polygon,
            contractAddress: "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359"): "usd-coin",
        TokenIdentityMapping.canonicalKey(
            chain: .bsc,
            contractAddress: "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d"): "usd-coin",
        TokenIdentityMapping.canonicalKey(
            chain: .scroll,
            contractAddress: "0x06efdbff2a14a7c8e15944d1f4a48f9f95f663a4"): "usd-coin"
    ]

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
