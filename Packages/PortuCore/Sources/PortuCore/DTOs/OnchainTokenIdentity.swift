import Foundation

public struct OnchainTokenIdentity: Hashable, Sendable {
    public let chain: Chain
    public let contractAddress: String

    public var canonicalPriceID: String {
        "asset:\(chain.rawValue.lowercased()):\(contractAddress)"
    }

    public var historicalPriceID: String {
        canonicalPriceID
    }

    public init?(historicalPriceID: String) {
        let normalized = historicalPriceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0] == "asset" || parts[0] == "zapper",
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

    /// Non-failable initializer for call sites that already hold a known-valid
    /// contract address (e.g. one previously round-tripped through SwiftData). Traps
    /// in debug builds on empty/whitespace input — earlier code silently kept the
    /// unnormalized string, which broke `Hashable` and `canonicalPriceID` parity.
    public init(chain: Chain, contractAddress: String) {
        guard let normalized = Self.normalizedContractAddress(contractAddress) else {
            assertionFailure(
                "OnchainTokenIdentity requires a non-empty contract address; got \(contractAddress.debugDescription)")
            self.chain = chain
            self.contractAddress = ""
            return
        }
        self.chain = chain
        self.contractAddress = normalized
    }

    private static func normalizedContractAddress(_ address: String?) -> String? {
        guard let address else { return nil }
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
