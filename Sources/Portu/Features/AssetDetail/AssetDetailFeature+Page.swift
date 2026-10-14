import Foundation
import PortuCore

extension AssetDetailFeature {
    static let unknownAccountName = "Unknown"

    /// The page seam: the header, holdings, per-chain breakdown and token rows of one asset from one
    /// valuation of the active accounts' tokens of that asset (A7: net basis, that asset). No row is
    /// ever hidden.
    ///
    /// Transitional: everything still prices from `legacyDisplayPrices`, the display-currency live
    /// book keyed by the raw CoinGecko ID, else the sync value; the header reads it under the chart
    /// key with the live 24h changes only.
    static func page(
        _ context: ValuationContext,
        asset: AssetDetailAsset,
        labels: [UUID: AssetDetailRowLabels],
        legacyDisplayPrices: [String: Decimal] = [:]) -> AssetDetailPage {
        let rate = context.usdToDisplayRate
        let entries = context.inputs.map { input in
            PositionTokenEntry(
                tokenId: input.tokenId,
                accountName: labels[input.tokenId]?.accountName ?? unknownAccountName,
                protocolName: labels[input.tokenId]?.protocolName,
                positionType: input.position.positionType,
                chain: input.position.chain,
                role: input.token.role,
                amount: input.token.amount,
                usdValue: input.token.usdValue,
                coinGeckoId: input.token.coinGeckoId)
        }
        let summary = computeHoldingsSummary(tokens: entries, prices: legacyDisplayPrices, fallbackUSDToDisplayRate: rate)
        let header = headerPriceInfo(
            coinGeckoId: effectiveHistoricalCoinGeckoID(
                assetCoinGeckoId: asset.coinGeckoId,
                onchainIdentity: asset.onchainIdentity,
                override: TokenPricingOverrideFeature.overridesByAssetId(context.overrides)[asset.id]),
            prices: legacyDisplayPrices,
            changes24h: context.prices.liveChanges24h)

        return AssetDetailPage(
            header: header.map { RowPricing(price: $0.price, source: .live, fraction24h: $0.change24h) },
            holdings: AssetHoldings(
                accountCount: summary.accountCount,
                totalAmount: summary.totalAmount,
                totalValue: summary.totalValue,
                chains: summary.byChain.map { chain in
                    AssetChainRow(
                        name: chain.name,
                        amount: entries
                            .filter { $0.role.isPositive && ($0.chain?.rawValue.capitalized ?? "Off-chain") == chain.name }
                            .reduce(Decimal.zero) { $0 + $1.amount },
                        value: chain.value,
                        share: chain.share)
                }),
            rows: aggregatePositionRows(tokens: entries, prices: legacyDisplayPrices, fallbackUSDToDisplayRate: rate).map { row in
                AssetPositionRow(
                    id: row.id,
                    accountName: row.accountName,
                    platformName: row.platformName,
                    context: row.context,
                    network: row.network,
                    amount: row.amount,
                    state: .counted,
                    value: row.usdBalance)
            })
    }
}
