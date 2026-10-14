import Foundation
import PortuCore

// MARK: - Headline (Overview top bar, Sidebar header)

struct OverviewHeadline: Equatable {
    let total: Decimal
    let change24h: Decimal
    /// `change / (total − change)`; `nil` shows "—".
    let changePercentage: Decimal?
}

extension OverviewFeature {
    /// The net total and its 24h change over every valued token (A1, A4).
    static func headline(_ context: ValuationContext) -> OverviewHeadline {
        let totals = context.valuation().totals
        let display = totals.display(rate: context.usdToDisplayRate)
        return OverviewHeadline(
            total: display.net,
            change24h: display.change24h,
            changePercentage: totals.changePercentage)
    }
}

// MARK: - Top Assets donut

struct OverviewTopAssets: Equatable {
    let slices: [OverviewAssetSlice]
    /// The hidden-balances line, in the display currency; `nil` when nothing is hidden.
    let hidden: HiddenBalances?
    /// The hidden line's share, rounded together with the slices so all of them sum to 100 (F4);
    /// `nil` when nothing is hidden or the gross total is not positive.
    let hiddenDisplayPercent: Int?

    var isEmpty: Bool {
        slices.isEmpty && hidden == nil
    }

    /// The slices drawn in the chart. A zero-value row (unpriced, shown) is a legend row only (S3).
    var chartSlices: [OverviewAssetSlice] {
        slices.filter { $0.value > 0 }
    }

    /// The hidden line's slice; `nil` when its gross is 0 and it is a legend row only (F3).
    var hiddenChartValue: Decimal? {
        guard let gross = hidden?.gross, gross > 0 else { return nil }
        return gross
    }
}

extension OverviewFeature {
    /// Gross assets (A7): the top rows, an "other" remainder and the hidden line (F5).
    static func topAssets(_ mode: TopAssetMode, context: ValuationContext) -> OverviewTopAssets {
        let tokens = context.valuation().tokens
        switch mode {
        case .assets:
            let list = DashboardList(tokens, basis: .gross, settings: context.settings) { assetRowKey($0) }
            let info = assetRowInfo(list.rows)
            return topAssets(
                list.ranked(top: 5) { isOrderedBeforeTie(info[$0.key], info[$1.key]) },
                residualID: assetResidualSliceID,
                rate: context.usdToDisplayRate) { row in
                    let asset = info[row.key]
                    return (asset?.rowID ?? "", asset?.label ?? "", asset?.logoURL)
                }
        case .category:
            let list = DashboardList(tokens, basis: .gross, settings: context.settings) { $0.token.portfolioCategory }
            return topAssets(
                list.ranked(top: 6) { isOrderedBeforeTie($0.key, $1.key) },
                residualID: categoryResidualSliceID,
                rate: context.usdToDisplayRate) { row in
                    (row.key.id.uuidString, row.key.name, nil)
                }
        }
    }

    private static func topAssets<Key>(
        _ ranked: RankedDashboardList<Key>,
        residualID: String,
        rate: Decimal,
        describe: (DashboardRow<Key>) -> (id: String, label: String, logoURL: String?)) -> OverviewTopAssets {
        var inputs = ranked.rows.map { row in
            let description = describe(row)
            return SliceInput(id: description.id, label: description.label, value: row.value, logoURL: description.logoURL)
        }
        if let remainder = ranked.remainder?.gross {
            inputs.append(SliceInput(id: residualID, label: "other", value: remainder, logoURL: nil))
        }
        let hidden = ranked.hidden
        // Shares come from the USD values, so the rounding never depends on the rate. The legend
        // shows whole percents. With no positive gross there is nothing to share out, and every
        // share shows "—" (F4).
        let shares = ranked.shares(fractionDigits: 2)
        let percent = { (share: Decimal?) in share.map { Int(truncating: ($0 * 100) as NSDecimalNumber) } }
        let sliceShares = shares.map { $0.rows + [$0.remainder].compactMap(\.self) }
        let slices = zip(inputs.indices, inputs).map { index, input in
            OverviewAssetSlice(
                id: input.id,
                label: input.label,
                value: input.value * rate,
                displayPercent: percent(sliceShares?[index]),
                colorIndex: index,
                logoURL: input.logoURL)
        }
        return OverviewTopAssets(
            slices: slices,
            hidden: hidden.isEmpty ? nil : hidden.display(rate: rate),
            hiddenDisplayPercent: percent(shares?.hidden))
    }

    // MARK: - Watchlist

    /// Held rows first, then watched coins that are not held. An ignored asset is in neither (S3,
    /// decided 2026-10-12). `assets` are every asset candidate, so a coin several assets share is
    /// judged on all of them.
    static func watchlistRows(
        _ context: ValuationContext,
        assets: [OverviewAssetCandidate],
        watchlistIDs: [String],
        portfolioLimit: Int = 10) -> [OverviewPriceRowData] {
        let market = context.prices.market
        let tokens = context.valuation(market: market).tokens
        let rate = context.usdToDisplayRate
        let list = DashboardList(tokens, basis: .net, settings: context.settings) { assetRowKey($0) }
        let info = assetRowInfo(list.rows)
        let held = list
            .ranked { isOrderedBeforeTie(info[$0.key], info[$1.key]) }
            .rows
            .filter { $0.value > 0 }
            .prefix(max(portfolioLimit, 0))

        let watchlist = OverviewWatchlistStore.normalizedUniqueIDs(watchlistIDs)
        let watchlistSet = Set(watchlist)
        var rows: [OverviewPriceRowData] = []
        var seenRowIDs: Set<String> = []
        var heldCoinGeckoIDs: Set<String> = []

        for row in held {
            guard let asset = info[row.key], seenRowIDs.insert(asset.rowID).inserted else { continue }
            let coinGeckoId = TokenIdentityMappingFeature.nonOnchainPriceID(asset.priceID)
            if let coinGeckoId {
                heldCoinGeckoIDs.insert(coinGeckoId)
            }
            let pricing = row.pricing.display(rate: rate)
            rows.append(OverviewPriceRowData(
                id: asset.rowID,
                assetId: asset.assetId,
                symbol: asset.label,
                name: asset.name,
                coinGeckoId: coinGeckoId,
                price: pricing.price,
                change24h: pricing.fraction24h,
                isWatchlisted: coinGeckoId.map { watchlistSet.contains($0) } ?? false,
                logoURL: asset.logoURL))
        }

        let ignoredAssets = TokenPricingOverrideFeature.ignoredAssetIds(context.overrides)
        let shownAssets = assetCandidatesByCoinGeckoId(from: assets.filter { !ignoredAssets.contains($0.id) })
            .merging(assetCandidatesByCoinGeckoId(from: assets)) { shown, _ in shown }
        let skipped = heldCoinGeckoIDs.union(ignoredWatchlistIDs(
            watchlist,
            tokens: tokens,
            assets: assets,
            context: context,
            ignoredAssets: ignoredAssets))
        for coinGeckoId in watchlist where !skipped.contains(coinGeckoId) && !seenRowIDs.contains(coinGeckoId) {
            seenRowIDs.insert(coinGeckoId)
            let quote = market.quote(priceID: coinGeckoId).display(rate: rate)
            let asset = shownAssets[coinGeckoId]
            rows.append(OverviewPriceRowData(
                id: coinGeckoId,
                assetId: asset?.id,
                symbol: asset?.symbol ?? coinGeckoId,
                name: asset?.name ?? coinGeckoId,
                coinGeckoId: coinGeckoId,
                price: quote.price,
                change24h: quote.fraction24h,
                isWatchlisted: true,
                logoURL: asset?.logoURL))
        }

        return rows
    }

    /// The user ignores an asset, not a coin: a watched coin is hidden only when at least one asset
    /// is priced under it and every such asset is ignored. Priced under it are the asset candidates
    /// carrying the ID and the assets of valued tokens, ignored ones included, whose non-onchain
    /// market price ID is the ID (identity mappings included; a manual price changes the value, not
    /// the coin). `ignoredAssets` follows the module's rule for which override applies.
    private static func ignoredWatchlistIDs(
        _ watchlist: [String],
        tokens: [ValuedToken],
        assets: [OverviewAssetCandidate],
        context: ValuationContext,
        ignoredAssets: Set<UUID>) -> Set<String> {
        let overrides = TokenPricingOverrideFeature.overridesByAssetId(context.overrides)
        let mappings = TokenIdentityMappingFeature.mappingsByIdentity(context.mappings)
        var pricedAssets: [String: Set<UUID>] = [:]
        for asset in assets {
            guard let coinGeckoId = TokenIdentityMappingFeature.normalizedProviderID(asset.coinGeckoId) else { continue }
            pricedAssets[coinGeckoId, default: []].insert(asset.id)
        }
        for token in tokens {
            let marketPriceID = TokenPricingOverrideFeature.marketPriceID(
                token: token.token,
                override: overrides[token.token.assetId],
                mappingsByIdentity: mappings)
            guard let coinGeckoId = TokenIdentityMappingFeature.nonOnchainPriceID(marketPriceID) else { continue }
            pricedAssets[coinGeckoId, default: []].insert(token.token.assetId)
        }
        return Set(watchlist.filter { coinGeckoId in
            guard let priced = pricedAssets[coinGeckoId], !priced.isEmpty else { return false }
            return priced.isSubset(of: ignoredAssets)
        })
    }

    // MARK: - Asset rows (donut asset mode, watchlist)

    /// One asset row: tokens that share a price ID and a symbol, else one asset.
    private struct AssetRowInfo {
        let rowID: String
        let assetId: UUID
        let label: String
        let name: String
        let priceID: String?
        let logoURL: String?
    }

    private static func assetRowKey(_ token: ValuedToken) -> String {
        assetAggregateKey(for: token.token, priceID: token.priceID)
    }

    /// The tokens in a visible Overview row (F2): the net asset rows, which hold every token the
    /// tabs, Key Changes, the donut's asset rows and the watchlist show, and the Health groups.
    static func visibleTokenIDs(_ tokens: [ValuedToken], settings: TokenDashboardSettings) -> Set<UUID> {
        let assetRows = DashboardList(tokens, basis: .net, settings: settings) { assetRowKey($0) }.visibleRows
        let healthRows = DashboardList(tokens, basis: .positiveNet, settings: settings) { PortfolioHealthGroupKey($0) }.visibleRows
        return Set(assetRows.lazy.flatMap(\.tokens).map(\.tokenId))
            .union(healthRows.lazy.flatMap(\.tokens).map(\.tokenId))
    }

    /// A row is described by its shown holdings: counted, non-ignored positive tokens, else (a
    /// borrow-only row) every token it has.
    private static func assetRowInfo(_ rows: [DashboardRow<String>]) -> [String: AssetRowInfo] {
        var info: [String: AssetRowInfo] = [:]
        for row in rows {
            let held = row.tokens.filter { $0.isCounted && !$0.isIgnored && $0.token.role.isPositive }
            info[row.key] = assetRowInfo(key: row.key, tokens: held.isEmpty ? row.tokens : held)
        }
        return info
    }

    private static func assetRowInfo(key: String, tokens: [ValuedToken]) -> AssetRowInfo? {
        guard let first = tokens.first else { return nil }
        let assetIds = Set(tokens.map(\.token.assetId))
        guard let assetId = assetIds.min(by: { $0.uuidString < $1.uuidString }) else { return nil }
        return AssetRowInfo(
            rowID: assetIds.count == 1 ? assetId.uuidString : key,
            assetId: assetId,
            label: displayLabel(symbol: first.token.symbol, name: first.token.name, priceID: first.priceID),
            name: first.token.name,
            priceID: TokenIdentityMappingFeature.normalizedHistoricalPriceID(tokens.lazy.compactMap(\.priceID).first),
            logoURL: tokens.lazy.compactMap(\.token.logoURL).first)
    }

    /// Equal values: label, then name, then row ID.
    private static func isOrderedBeforeTie(_ lhs: AssetRowInfo?, _ rhs: AssetRowInfo?) -> Bool {
        guard let lhs, let rhs else { return false }
        let labelOrder = lhs.label.localizedStandardCompare(rhs.label)
        if labelOrder != .orderedSame {
            return labelOrder == .orderedAscending
        }
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.rowID < rhs.rowID
    }

    /// Equal values: sort order, then name, then ID.
    private static func isOrderedBeforeTie(_ lhs: PortfolioCategorySnapshot, _ rhs: PortfolioCategorySnapshot) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

// MARK: - Summary cards

struct OverviewSummaryCardRow: Equatable, Identifiable {
    let label: String
    let value: Decimal

    var id: String {
        label
    }
}

struct OverviewSummaryCard: Equatable, Identifiable {
    let title: String
    let rows: [OverviewSummaryCardRow]

    var id: String {
        title
    }
}

extension OverviewSummaryCardsFeature {
    /// Idle, Deployed and Debt in display order (A3). The rows are fixed and never display-filtered.
    static func cards(
        _ context: ValuationContext,
        categories: [PortfolioCategorySnapshot]) -> [OverviewSummaryCard] {
        let cards = context.valuation().summaryCards.display(rate: context.usdToDisplayRate)
        return [
            OverviewSummaryCard(title: "Idle", rows: [
                OverviewSummaryCardRow(label: "Stablecoins & Fiat", value: cards.idle.stablecoinsAndFiat),
                OverviewSummaryCardRow(
                    label: OverviewSummaryLabels.majorCategoryTitle(categories: categories),
                    value: cards.idle.majors),
                OverviewSummaryCardRow(label: "Tokens & Memecoins", value: cards.idle.tokensAndMemecoins)
            ]),
            OverviewSummaryCard(title: "Deployed", rows: [
                OverviewSummaryCardRow(label: "Lending", value: cards.deployed.lending),
                OverviewSummaryCardRow(label: "Staked", value: cards.deployed.staked),
                OverviewSummaryCardRow(label: "Yield", value: cards.deployed.yield),
                OverviewSummaryCardRow(label: "Other", value: cards.deployed.other)
            ]),
            OverviewSummaryCard(title: "Debt", rows: [
                OverviewSummaryCardRow(label: "Borrowed", value: cards.debt)
            ])
        ]
    }
}

// MARK: - Portfolio health

struct PortfolioHealthData: Equatable {
    /// The visible symbol + name groups, largest first. `percentage` is the unrounded share of the
    /// floored total.
    let weights: [AssetWeight]
    let metrics: DiversificationMetrics
    /// Groups at or above the concentration threshold, largest first, over every group (S3).
    let concentrationRisks: [ConcentrationRisk]
    /// The expanded list's hidden-balances line, in the display currency; `nil` when nothing is hidden.
    let hidden: HiddenBalances?
    /// The weights and the hidden line rounded together so they sum to 100% (F4).
    let displayShares: ListShares?
}

/// The Health weight list as shown. The collapsed preview is the top rows with their unrounded
/// weights and no hidden line (exempt in A7). The full list shows F4 shares and the hidden line.
struct PortfolioHealthWeightList: Equatable {
    struct Row: Equatable, Identifiable {
        let weight: AssetWeight
        /// `nil` shows "—".
        let share: Decimal?

        var id: PortfolioHealthGroupKey {
            weight.id
        }
    }

    static let previewCount = 5

    let rows: [Row]
    let isExpanded: Bool
    let hidden: HiddenBalances?
    let hiddenShare: Decimal?
}

extension PortfolioHealthData {
    /// A list with no more rows than the preview is always shown in full.
    func weightList(showAll: Bool) -> PortfolioHealthWeightList {
        guard showAll || weights.count <= PortfolioHealthWeightList.previewCount else {
            return PortfolioHealthWeightList(
                rows: weights.prefix(PortfolioHealthWeightList.previewCount).map { .init(weight: $0, share: $0.percentage) },
                isExpanded: false,
                hidden: nil,
                hiddenShare: nil)
        }
        let shares = displayShares?.rows.count == weights.count ? displayShares?.rows : nil
        return PortfolioHealthWeightList(
            rows: weights.indices.map { .init(weight: weights[$0], share: shares?[$0]) },
            isExpanded: true,
            hidden: hidden,
            hiddenShare: displayShares?.hidden)
    }
}

extension PortfolioHealthFeature {
    /// Weights per symbol + name group, net and floored at 0 (A7), and the metrics and concentration
    /// risks over every such group, hidden ones included (S3). Only counted tokens that are not
    /// ignored can mark a group as a stablecoin.
    static func health(_ context: ValuationContext) -> PortfolioHealthData {
        let valuation = context.valuation()
        let rate = context.usdToDisplayRate
        let list = DashboardList(valuation.tokens, basis: .positiveNet, settings: context.settings) {
            PortfolioHealthGroupKey($0)
        }
        let ranked = list.ranked { lhs, rhs in
            lhs.key.symbol != rhs.key.symbol ? lhs.key.symbol < rhs.key.symbol : lhs.key.name < rhs.key.name
        }
        let weight = { (row: DashboardRow<PortfolioHealthGroupKey>) in
            AssetWeight(
                symbol: row.key.symbol,
                name: row.key.name,
                usdValue: row.displayValue(rate: rate),
                percentage: list.weight(of: row) ?? 0)
        }
        let chainCount = Set(valuation.tokens.filter { $0.isCounted && $0.isValued }.compactMap(\.position.chain)).count
        let everyGroup = list.rows.map(weight).sorted {
            $0.percentage != $1.percentage ? $0.percentage > $1.percentage : ($0.symbol, $0.name) < ($1.symbol, $1.name)
        }

        return PortfolioHealthData(
            weights: ranked.rows.map(weight),
            metrics: computeDiversificationMetrics(
                tokens: valuation.tokens.filter { $0.isCounted && !$0.isIgnored }.map(\.token),
                weights: everyGroup,
                chainCount: chainCount),
            concentrationRisks: computeConcentrationRisks(weights: everyGroup, threshold: concentrationThreshold),
            hidden: list.hidden.isEmpty ? nil : list.hidden.display(rate: rate),
            displayShares: ranked.shares())
    }
}
