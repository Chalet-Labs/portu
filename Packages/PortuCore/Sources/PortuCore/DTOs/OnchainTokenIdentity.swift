import Foundation

public struct OnchainTokenIdentity: Hashable, Sendable {
    /// Existing provider-neutral convention for native assets on EVM-compatible
    /// chains. APIs that omit a native contract address normalize to this value.
    public static let nativeAssetSentinel = "0x0000000000000000000000000000000000000000"

    public let chain: Chain
    public let contractAddress: String

    public var canonicalPriceID: String {
        "asset:\(chain.rawValue.lowercased()):\(contractAddress)"
    }

    public var historicalPriceID: String {
        canonicalPriceID
    }

    public init?(historicalPriceID: String) {
        let trimmed = historicalPriceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].lowercased() == "asset" || parts[0].lowercased() == "zapper",
            let chain = Chain.normalized(rawValue: String(parts[1])),
            let contractAddress = Self.normalizedContractAddress(String(parts[2]), chain: chain)
        else {
            return nil
        }
        self.chain = chain
        self.contractAddress = contractAddress
    }

    public init?(chain: Chain?, contractAddress: String?) {
        guard let chain, let normalized = Self.normalizedContractAddress(contractAddress, chain: chain) else {
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
        guard let normalized = Self.normalizedContractAddress(contractAddress, chain: chain) else {
            assertionFailure(
                "OnchainTokenIdentity requires a non-empty contract address; got \(contractAddress.debugDescription)")
            self.chain = chain
            self.contractAddress = ""
            return
        }
        self.chain = chain
        self.contractAddress = normalized
    }

    public static func native(on chain: Chain) -> Self {
        Self(chain: chain, contractAddress: nativeAssetSentinel)
    }

    public static func normalizedHistoricalPriceID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(historicalPriceID: trimmed)?.historicalPriceID ?? trimmed.lowercased()
    }

    private static func normalizedContractAddress(_ address: String?, chain: Chain) -> String? {
        guard let address else { return nil }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "native" {
            return nativeAssetSentinel
        }
        let normalized = chain == .solana ? trimmed : trimmed.lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
