import Foundation

public struct OnchainTokenIdentity: Hashable, Sendable {
    public let chain: Chain
    public let contractAddress: String

    public var historicalPriceID: String {
        "zapper:\(chain.rawValue.lowercased()):\(contractAddress)"
    }

    public init?(historicalPriceID: String) {
        let normalized = historicalPriceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0] == "zapper",
            let chain = Chain.normalized(rawValue: String(parts[1])),
            let contractAddress = Self.normalizedContractAddress(String(parts[2]))
        else {
            return nil
        }
        self.chain = chain
        self.contractAddress = contractAddress
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
