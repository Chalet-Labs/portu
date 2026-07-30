import PortuCore

public enum ZerionChainMapping {
    /// Verified against GET /v1/chains/ on 2026-07-26.
    static let verified: [Chain: String] = [
        .ethereum: "ethereum",
        .polygon: "polygon",
        .arbitrum: "arbitrum",
        .optimism: "optimism",
        .base: "base",
        .bsc: "binance-smart-chain",
        .degen: "degen",
        .gnosis: "xdai",
        .celo: "celo",
        .opBNB: "opbnb",
        .unichain: "unichain",
        .berachain: "berachain",
        .sonic: "sonic",
        .zksync: "zksync-era",
        .polygonZkEVM: "polygon-zkevm",
        .ronin: "ronin",
        .mantle: "mantle",
        .mode: "mode",
        .linea: "linea",
        .blast: "blast",
        .taiko: "taiko",
        .scroll: "scroll",
        .hyperEVM: "hyperevm",
        .zora: "zora",
        .solana: "solana",
        .avalanche: "avalanche",
        .monad: "monad",
        .katana: "katana"
    ]

    /// Present in Zerion's chain catalog but rejected by wallet positions on 2026-07-27.
    private static let unsupportedPositionChains: Set<Chain> = [
        .mode,
        .opBNB,
        .ronin,
        .taiko
    ]

    static var genericEVMChainIDChunks: [[String]] {
        verified
            .filter { $0.key != .solana && !unsupportedPositionChains.contains($0.key) }
            .map(\.value)
            .sorted()
            .chunked(size: 25)
    }

    public static var supportedEVMPositionChainCount: Int {
        verified.keys.count { $0 != .solana && supportsPositions(on: $0) }
    }

    static var analyticsChainIDs: [String] {
        (genericEVMChainIDChunks.flatMap(\.self) + ["solana"]).sorted()
    }

    static func id(for chain: Chain) throws -> String {
        guard let id = verified[chain] else {
            throw ZerionError.unsupportedChain(chain.rawValue)
        }
        return id
    }

    static func positionID(for chain: Chain) throws -> String {
        guard !unsupportedPositionChains.contains(chain) else {
            throw ZerionError.unsupportedChain(chain.rawValue)
        }
        return try id(for: chain)
    }

    public static func supportsPositions(on chain: Chain) -> Bool {
        (try? positionID(for: chain)) != nil
    }

    static func chain(for id: String) throws -> Chain {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let chain = verified.first(where: { $0.value == normalized })?.key else {
            throw ZerionError.invalidData("unknown chain \(normalized)")
        }
        return chain
    }

    static func implementation(for identity: OnchainTokenIdentity) throws -> String {
        let chainID = try id(for: identity.chain)
        if identity.contractAddress == OnchainTokenIdentity.nativeAssetSentinel {
            return chainID
        }
        return "\(chainID):\(identity.contractAddress)"
    }

    static func identity(for implementation: String) throws -> OnchainTokenIdentity {
        let parts = implementation.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let chainID = parts.first, !chainID.isEmpty else {
            throw ZerionError.invalidData("empty implementation")
        }
        let chain = try chain(for: String(chainID))
        if parts.count == 1 || parts[1].isEmpty {
            return .native(on: chain)
        }
        return OnchainTokenIdentity(chain: chain, contractAddress: String(parts[1]))
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
