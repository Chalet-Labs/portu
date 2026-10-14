import Foundation
import PortuCore

/// The asset fields Asset Detail values with, read from the model once. An asset held nowhere has
/// no token, so its market quote resolves from these.
struct AssetDetailAsset: Equatable {
    let id: UUID
    let symbol: String
    let name: String
    let category: AssetCategory
    let coinGeckoId: String?
    let onchainIdentity: OnchainTokenIdentity?
}

/// What a token row shows besides its valuation: the names the position context does not carry.
struct AssetDetailRowLabels: Equatable {
    let accountName: String
    let protocolName: String?
}

/// The boundary between SwiftData and Asset Detail: the page reads every model here, once, at the
/// top of its body pass (#103); only value types cross.
struct AssetDetailProjection: Equatable {
    let asset: AssetDetailAsset
    /// The active accounts' tokens of this asset.
    let inputs: [ValuationInput]
    /// Keyed by `ValuationInput.tokenId`.
    let labels: [UUID: AssetDetailRowLabels]

    @MainActor
    init(_ asset: Asset, tokens: [PositionToken]) {
        let assetId = asset.id
        let held = tokens.filter { $0.asset?.id == assetId }
        self.asset = AssetDetailAsset(
            id: assetId,
            symbol: asset.symbol,
            name: asset.name,
            category: asset.category,
            coinGeckoId: asset.coinGeckoId,
            onchainIdentity: OnchainTokenIdentity(chain: asset.upsertChain, contractAddress: asset.upsertContract))
        self.inputs = ValuationInput.activeAccounts(held)
        self.labels = Dictionary(
            held.compactMap { token in
                token.position.map { position in
                    (token.id, AssetDetailRowLabels(
                        accountName: position.account?.name ?? AssetDetailFeature.unknownAccountName,
                        protocolName: position.protocolName))
                }
            },
            uniquingKeysWith: { first, _ in first })
    }
}

/// The page as shown, money in the display currency.
struct AssetDetailPage: Equatable {
    /// The header card's price and 24h fraction; `nil` shows no card.
    let header: RowPricing?
    let holdings: AssetHoldings
    let rows: [AssetPositionRow]
    /// The price chart's cache key. It ignores identity mappings, which the backfill writer honours;
    /// that divergence is out of scope for PR (b) (spec, Out of scope).
    let chartPriceID: String?
}

struct AssetHoldings: Equatable {
    let accountCount: Int
    let totalAmount: Decimal
    let totalValue: Decimal
    let chains: [AssetChainRow]
}

/// One chain of the per-chain breakdown.
struct AssetChainRow: Equatable, Identifiable {
    let name: String
    let amount: Decimal
    let value: Decimal
    /// The rounded share; `nil` shows "—".
    let share: Decimal?

    var id: String {
        name
    }
}

/// One token. `value` is the signed contribution of a counted row and the unsigned value of a
/// not-counted one; an unpriced or ignored row has none (U4).
struct AssetPositionRow: Equatable, Identifiable {
    let id: UUID
    let accountName: String
    let platformName: String
    let context: String
    let network: String
    let amount: Decimal
    let state: TokenRowState
    let value: Decimal?
}

enum AssetDetailFormat {
    static func currency(_ value: Decimal, code: String) -> String {
        value.formatted(.currency(code: code))
    }

    static func amount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2 ... 8)))
    }

    static func share(_ share: Decimal?) -> String {
        share.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—"
    }

    static func change(_ fraction: Decimal) -> String {
        fraction.formatted(.percent.precision(.fractionLength(2)))
    }
}
