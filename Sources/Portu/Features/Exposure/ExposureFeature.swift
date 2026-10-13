import Foundation
import PortuCore

enum ExposureFeature {
    /// The Exposure page from one valuation of the context: a category table and an asset table,
    /// each a net list whose rows carry spot, liabilities and net (A7) and end with the table's
    /// hidden line; the summary over every valued token; and the polled IDs (S12).
    static func dashboard(_ context: ValuationContext) -> ExposureDashboardData {
        let valuation = context.valuation()
        let rate = context.usdToDisplayRate
        let categories = DashboardList(valuation.tokens, basis: .net, settings: context.settings) {
            $0.token.portfolioCategory
        }
        let assets = DashboardList(valuation.tokens, basis: .net, settings: context.settings) { $0.token.assetId }
        let categoryRanked = categories.ranked { isOrderedBeforeTie($0.key, $1.key) }
        let assetInfo = assets.rows.reduce(into: [UUID: AssetRowInfo]()) { info, row in
            info[row.key] = AssetRowInfo(row)
        }
        let assetRanked = assets.ranked { isOrderedBeforeTie(assetInfo[$0.key], assetInfo[$1.key]) }

        return ExposureDashboardData(
            categoryRows: categoryRanked.rows.map { row in
                let totals = row.totals.display(rate: rate)
                return CategoryExposure(
                    id: row.key.id.uuidString,
                    name: row.key.name,
                    spotAssets: totals.gross,
                    liabilities: totals.debt,
                    shareOfSpot: categories.ratio(of: row, to: .gross))
            },
            assetRows: assetRanked.rows.compactMap { row in
                guard let info = assetInfo[row.key] else { return nil }
                let totals = row.totals.display(rate: rate)
                return AssetExposure(
                    id: row.key,
                    symbol: info.symbol,
                    spotAssets: totals.gross,
                    liabilities: totals.debt,
                    logoURL: info.logoURL,
                    shareOfSpot: assets.ratio(of: row, to: .gross))
            },
            categoryHidden: ExposureHiddenRow(categoryRanked.hidden, rate: rate),
            assetHidden: ExposureHiddenRow(assetRanked.hidden, rate: rate),
            summary: summary(valuation, rate: rate),
            pollingIDs: pollingIDs(valuation.tokens, visibleRows: assets.visibleRows))
    }

    /// Spot, Liabilities and Net total over every valued token, dust and hidden rows included, so
    /// Net total is the Overview headline. Net exposure leaves out the stablecoin category.
    private static func summary(_ valuation: PortfolioValuation, rate: Decimal) -> ExposureSummary {
        let totals = valuation.totals
        let exposure = valuation.totals { $0.token.portfolioCategory.semanticRole != .stablecoin }
        let display = totals.display(rate: rate)
        return ExposureSummary(
            totalSpot: display.gross,
            totalLiabilities: display.debt,
            netTotal: display.net,
            netExposure: exposure.display(rate: rate).net,
            netExposureShare: totals.gross > 0 ? exposure.net / totals.gross : nil)
    }

    /// A counted, non-ignored token with a price ID is polled while its asset row is visible, and
    /// always when it has no usable price (valued from its sync value, or unpriced), so it can get
    /// one. A manual price needs no polling. No ranking, cap or watchlist (decided 2026-10-13).
    private static func pollingIDs(_ tokens: [ValuedToken], visibleRows: [DashboardRow<UUID>]) -> [String] {
        let visible = Set(visibleRows.lazy.flatMap(\.tokens).map(\.tokenId))
        let ids = tokens.compactMap { token -> String? in
            guard let priceID = token.priceID, token.isCounted else { return nil }
            switch token.source {
            case .live, .close:
                return visible.contains(token.tokenId) ? priceID : nil
            case .sync, .unpriced:
                return priceID
            case .manual, .ignored:
                return nil
            }
        }
        return Array(Set(ids)).sorted()
    }

    /// What an asset row shows besides its values: its counted, non-ignored tokens, else (an
    /// unpriced or borrow-only row) any of its tokens. The tokens share one asset, so any of them
    /// names it; the logo is the one of the lowest token ID that has one, whatever the query order.
    private struct AssetRowInfo {
        let id: UUID
        let symbol: String
        let logoURL: String?

        init?(_ row: DashboardRow<UUID>) {
            let held = row.tokens.filter { $0.isCounted && !$0.isIgnored }
            let tokens = held.isEmpty ? row.tokens : held
            guard let first = tokens.first else { return nil }
            self.id = row.key
            self.symbol = first.token.symbol
            self.logoURL = tokens
                .filter { $0.token.logoURL != nil }
                .min { $0.tokenId.uuidString < $1.tokenId.uuidString }?
                .token.logoURL
        }
    }

    /// Equal nets: name, then ID.
    private static func isOrderedBeforeTie(_ lhs: PortfolioCategorySnapshot, _ rhs: PortfolioCategorySnapshot) -> Bool {
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Equal nets: symbol, then asset ID.
    private static func isOrderedBeforeTie(_ lhs: AssetRowInfo?, _ rhs: AssetRowInfo?) -> Bool {
        guard let lhs, let rhs else { return false }
        let symbolOrder = lhs.symbol.localizedStandardCompare(rhs.symbol)
        if symbolOrder != .orderedSame {
            return symbolOrder == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
