import Foundation

public enum Chain: String, Codable, CaseIterable, Sendable {
    case ethereum
    case polygon
    case arbitrum
    case optimism
    case base
    case bsc
    case gnosis
    case unichain
    case berachain
    case sonic
    case zksync
    case polygonZkEVM
    case moonbeam
    case ronin
    case mantle
    case immutableX
    case mode
    case linea
    case blast
    case taiko
    case scroll
    case hyperliquid
    case zora
    case solana
    case bitcoin
    case avalanche
    case monad
    case katana
}

public extension Chain {
    static func normalized(rawValue: String) -> Chain? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { $0.rawValue.lowercased() == normalized }
    }
}
