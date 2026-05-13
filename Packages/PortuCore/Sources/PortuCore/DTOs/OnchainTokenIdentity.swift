import Foundation

public struct OnchainTokenIdentity: Hashable, Sendable {
    public let chain: Chain
    public let contractAddress: String

    public var historicalPriceID: String {
        "zapper:\(chain.rawValue):\(contractAddress)"
    }

    public init?(chain: Chain?, contractAddress: String?) {
        guard let chain, let normalized = Self.normalizedContractAddress(contractAddress) else {
            return nil
        }
        self.chain = chain
        self.contractAddress = normalized
    }

    public init(chain: Chain, contractAddress: String) {
        self.chain = chain
        self.contractAddress = Self.normalizedContractAddress(contractAddress) ?? contractAddress
    }

    private static func normalizedContractAddress(_ address: String?) -> String? {
        guard let address else { return nil }
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
