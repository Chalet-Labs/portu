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

    var coinGeckoAssetPlatformID: String? {
        switch self {
        case .ethereum: "ethereum"
        case .polygon: "polygon-pos"
        case .arbitrum: "arbitrum-one"
        case .optimism: "optimistic-ethereum"
        case .base: "base"
        case .bsc: "binance-smart-chain"
        case .gnosis: "xdai"
        case .unichain: "unichain"
        case .berachain: "berachain"
        case .sonic: "sonic"
        case .zksync: "zksync"
        case .polygonZkEVM: "polygon-zkevm"
        case .moonbeam: "moonbeam"
        case .ronin: "ronin"
        case .mantle: "mantle"
        case .immutableX: "immutable"
        case .mode: "mode"
        case .linea: "linea"
        case .blast: "blast"
        case .taiko: "taiko"
        case .scroll: "scroll"
        case .hyperliquid: "hyperliquid"
        case .zora: "zora-network"
        case .solana: "solana"
        case .bitcoin: nil
        case .avalanche: "avalanche"
        case .monad: "monad"
        case .katana: "katana"
        }
    }

    var coinGeckoOnchainNetworkID: String? {
        switch self {
        case .ethereum: "eth"
        case .polygon: "polygon_pos"
        case .arbitrum: "arbitrum"
        case .optimism: "optimism"
        case .base: "base"
        case .bsc: "bsc"
        case .gnosis: "xdai"
        case .unichain: "unichain"
        case .berachain: "berachain"
        case .sonic: "sonic"
        case .zksync: "zksync"
        case .polygonZkEVM: "polygon-zkevm"
        case .moonbeam: "moonbeam"
        case .ronin: "ronin"
        case .mantle: "mantle"
        case .immutableX: "immutablex"
        case .mode: "mode"
        case .linea: "linea"
        case .blast: "blast"
        case .taiko: "taiko"
        case .scroll: "scroll"
        case .hyperliquid: nil
        case .zora: "zora"
        case .solana: "solana"
        case .bitcoin: nil
        case .avalanche: "avax"
        case .monad: nil
        case .katana: nil
        }
    }
}
