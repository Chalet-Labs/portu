import Foundation
import PortuCore

struct AssetLookupCache {
    private var byCoinGeckoId: [String: Asset] = [:]
    private var byChainContract: [ChainContractAssetKey: Asset] = [:]
    private var bySourceKey: [String: Asset] = [:]

    init(assets: [Asset]) {
        for asset in assets {
            record(asset)
        }
    }

    mutating func record(_ asset: Asset) {
        if let coinGeckoId = asset.coinGeckoId, !coinGeckoId.isEmpty {
            if byCoinGeckoId[coinGeckoId] == nil {
                byCoinGeckoId[coinGeckoId] = asset
            }
        }
        if
            let chain = asset.upsertChain,
            let contract = asset.upsertContract,
            !contract.isEmpty {
            let key = ChainContractAssetKey(chain: chain, contract: contract)
            if byChainContract[key] == nil {
                byChainContract[key] = asset
            }
        }
        if let sourceKey = asset.sourceKey, !sourceKey.isEmpty {
            if bySourceKey[sourceKey] == nil {
                bySourceKey[sourceKey] = asset
            }
        }
    }

    func asset(coinGeckoId: String) -> Asset? {
        byCoinGeckoId[coinGeckoId]
    }

    func asset(chain: Chain, contract: String) -> Asset? {
        byChainContract[ChainContractAssetKey(chain: chain, contract: contract)]
    }

    func asset(sourceKey: String) -> Asset? {
        bySourceKey[sourceKey]
    }
}

private struct ChainContractAssetKey: Hashable {
    let chain: Chain
    let contract: String

    init(chain: Chain, contract: String) {
        self.chain = chain
        let trimmed = contract.trimmingCharacters(in: .whitespacesAndNewlines)
        self.contract = chain == .solana ? trimmed : trimmed.lowercased()
    }
}
