import Foundation
import SwiftData

@Model
public final class TokenIdentityMapping {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var canonicalKey: String
    public var chain: Chain
    public var contractAddress: String
    public var coinGeckoId: String?
    public var zapperId: String?
    public var coinGeckoResolvedAt: Date?
    public var zapperResolvedAt: Date?
    public var lastCoinGeckoFailureAt: Date?
    public var lastZapperFailureAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        chain: Chain,
        contractAddress: String,
        coinGeckoId: String? = nil,
        zapperId: String? = nil,
        coinGeckoResolvedAt: Date? = nil,
        zapperResolvedAt: Date? = nil,
        lastCoinGeckoFailureAt: Date? = nil,
        lastZapperFailureAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now) {
        let normalizedContract = Self.normalizedContractAddress(contractAddress)
        self.id = id
        self.canonicalKey = Self.canonicalKey(chain: chain, contractAddress: normalizedContract)
        self.chain = chain
        self.contractAddress = normalizedContract
        self.coinGeckoId = Self.normalizedProviderID(coinGeckoId)
        self.zapperId = Self.normalizedProviderID(zapperId)
        self.coinGeckoResolvedAt = coinGeckoResolvedAt
        self.zapperResolvedAt = zapperResolvedAt
        self.lastCoinGeckoFailureAt = lastCoinGeckoFailureAt
        self.lastZapperFailureAt = lastZapperFailureAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public convenience init(
        id: UUID = UUID(),
        identity: OnchainTokenIdentity,
        coinGeckoId: String? = nil,
        zapperId: String? = nil,
        coinGeckoResolvedAt: Date? = nil,
        zapperResolvedAt: Date? = nil,
        lastCoinGeckoFailureAt: Date? = nil,
        lastZapperFailureAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now) {
        self.init(
            id: id,
            chain: identity.chain,
            contractAddress: identity.contractAddress,
            coinGeckoId: coinGeckoId,
            zapperId: zapperId,
            coinGeckoResolvedAt: coinGeckoResolvedAt,
            zapperResolvedAt: zapperResolvedAt,
            lastCoinGeckoFailureAt: lastCoinGeckoFailureAt,
            lastZapperFailureAt: lastZapperFailureAt,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }

    public var onchainIdentity: OnchainTokenIdentity {
        OnchainTokenIdentity(chain: chain, contractAddress: contractAddress)
    }

    public func updateCoinGeckoId(_ coinGeckoId: String?, resolvedAt: Date) {
        self.coinGeckoId = Self.normalizedProviderID(coinGeckoId)
        coinGeckoResolvedAt = resolvedAt
        lastCoinGeckoFailureAt = nil
        updatedAt = resolvedAt
    }

    public static func canonicalKey(for identity: OnchainTokenIdentity) -> String {
        canonicalKey(chain: identity.chain, contractAddress: identity.contractAddress)
    }

    public static func canonicalKey(chain: Chain, contractAddress: String) -> String {
        "\(chain.rawValue):\(normalizedContractAddress(contractAddress))"
    }

    public static func normalizedContractAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedProviderID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
