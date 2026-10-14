import Foundation
import PortuCore

extension AssetDetailFeature {
    static let unknownAccountName = "Unknown"
    static let walletPlatformName = "Wallet"
    static let offChainNetworkName = "Off-chain"

    /// The page seam: the header, holdings, per-chain breakdown and token rows of one asset from one
    /// valuation of the active accounts' tokens of that asset (A7: net basis, that asset). Values are
    /// summed in USD and converted once. No token row is ever hidden; reward-only and ignored chains
    /// drop out of the per-chain list.
    static func page(
        _ context: ValuationContext,
        asset: AssetDetailAsset,
        labels: [UUID: AssetDetailRowLabels]) -> AssetDetailPage {
        let market = context.prices.market
        let valuation = context.valuation(market: market)
        let rate = context.usdToDisplayRate
        return AssetDetailPage(
            header: header(valuation, market: market, asset: asset, context: context),
            holdings: holdings(valuation, rate: rate),
            rows: rows(valuation, labels: labels, rate: rate))
    }

    static func networkName(_ chain: Chain?) -> String {
        chain?.rawValue.capitalized ?? offChainNetworkName
    }

    /// U3: a held asset follows V5 and shows no card when nothing it holds is valued. An asset with
    /// no counted, non-ignored token (unheld, reward-only or ignored) shows the market quote: the
    /// live price, else the latest close, under its market price ID.
    private static func header(
        _ valuation: PortfolioValuation,
        market: MarketPrices,
        asset: AssetDetailAsset,
        context: ValuationContext) -> RowPricing? {
        let isHeld = valuation.tokens.contains { $0.isCounted && !$0.isIgnored }
        let pricing = isHeld
            ? RowPricing(tokens: valuation.tokens)
            : market.quote(priceID: marketPriceID(of: asset, context: context))
        let shown = pricing.display(rate: context.usdToDisplayRate)
        return shown.price == nil ? nil : shown
    }

    /// The asset's own market price ID. An unheld asset has no token to resolve it from, so the
    /// asset stands in as a zero-amount balance.
    private static func marketPriceID(of asset: AssetDetailAsset, context: ValuationContext) -> String? {
        let entry = TokenEntry(
            assetId: asset.id,
            symbol: asset.symbol,
            name: asset.name,
            category: asset.category,
            coinGeckoId: asset.coinGeckoId,
            onchainIdentity: asset.onchainIdentity,
            role: .balance,
            amount: 0,
            usdValue: 0)
        return TokenPricingOverrideFeature.marketPriceID(
            token: entry,
            override: TokenPricingOverrideFeature.overridesByAssetId(context.overrides)[asset.id],
            mappingsByIdentity: TokenIdentityMappingFeature.mappingsByIdentity(context.mappings))
    }

    /// Total Value is Σ contributions; Total Amount leaves out ignored tokens; accounts are counted by
    /// ID. Each chain shows its net amount and net value with F4 shares on the net basis; the list
    /// shows every chain (`showAll`), and a chain with nothing counted (rewards only) has no row.
    private static func holdings(_ valuation: PortfolioValuation, rate: Decimal) -> AssetHoldings {
        let chains = DashboardList(valuation.tokens, basis: .net, settings: .showAll) { $0.position.chain }
            .ranked { networkName($0.key).localizedStandardCompare(networkName($1.key)) == .orderedAscending }
        let shares: [Decimal?] = chains.shares()?.rows ?? Array(repeating: nil, count: chains.rows.count)

        return AssetHoldings(
            accountCount: Set(valuation.tokens.compactMap(\.position.accountId)).count,
            totalAmount: valuation.totals(where: { !$0.isIgnored }).netAmount,
            totalValue: valuation.totals.display(rate: rate).net,
            chains: zip(chains.rows, shares).map { row, share in
                let totals = row.totals.display(rate: rate)
                return AssetChainRow(name: networkName(row.key), amount: totals.netAmount, value: totals.net, share: share)
            })
    }

    /// U4: a counted row shows its signed contribution, a not-counted one (a reward or an amount ≤ 0)
    /// its own unsigned value; an unpriced or ignored row has no value. Rows sort by contribution
    /// descending, then account name, then token ID.
    private static func rows(
        _ valuation: PortfolioValuation,
        labels: [UUID: AssetDetailRowLabels],
        rate: Decimal) -> [AssetPositionRow] {
        let accountName = { (token: ValuedToken) in labels[token.tokenId]?.accountName ?? unknownAccountName }
        let sorted = valuation.tokens.sorted { lhs, rhs in
            if lhs.contribution != rhs.contribution {
                return lhs.contribution > rhs.contribution
            }
            let order = accountName(lhs).localizedStandardCompare(accountName(rhs))
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return lhs.tokenId.uuidString < rhs.tokenId.uuidString
        }
        return sorted.map { token in
            let shown = token.display(rate: rate)
            let value: Decimal? = switch token.rowState {
            case .counted: shown.contribution
            case .notCounted: shown.value
            case .unpriced, .ignored: nil
            }
            return AssetPositionRow(
                id: token.tokenId,
                accountName: accountName(token),
                platformName: labels[token.tokenId]?.protocolName ?? walletPlatformName,
                context: token.position.positionType.rawValue.capitalized,
                network: networkName(token.position.chain),
                amount: token.token.amount,
                state: token.rowState,
                value: value)
        }
    }
}
