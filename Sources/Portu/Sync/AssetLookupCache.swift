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
        if let coinGeckoId = normalizedLookupKey(asset.coinGeckoId) {
            if byCoinGeckoId[coinGeckoId] == nil {
                byCoinGeckoId[coinGeckoId] = asset
            }
        }
        if
            let chain = asset.upsertChain,
            let contract = normalizedLookupKey(asset.upsertContract) {
            let key = ChainContractAssetKey(chain: chain, contract: contract)
            if byChainContract[key] == nil {
                byChainContract[key] = asset
            }
        }
        if let sourceKey = normalizedLookupKey(asset.sourceKey) {
            if bySourceKey[sourceKey] == nil {
                bySourceKey[sourceKey] = asset
            }
        }
    }

    func asset(coinGeckoId: String) -> Asset? {
        guard let coinGeckoId = normalizedLookupKey(coinGeckoId) else { return nil }
        return byCoinGeckoId[coinGeckoId]
    }

    func asset(chain: Chain, contract: String) -> Asset? {
        guard let contract = normalizedLookupKey(contract) else { return nil }
        return byChainContract[ChainContractAssetKey(chain: chain, contract: contract)]
    }

    func asset(sourceKey: String) -> Asset? {
        guard let sourceKey = normalizedLookupKey(sourceKey) else { return nil }
        return bySourceKey[sourceKey]
    }

    private func normalizedLookupKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
