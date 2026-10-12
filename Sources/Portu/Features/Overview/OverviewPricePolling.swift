import Foundation
import PortuCore

extension OverviewFeature {
    /// The live-polling set: the top holdings by selection value, then the watchlist (S12). Values
    /// and usable prices come from the module; the selection and ranking rules are polling's own.
    static func pricePollingIDs(
        _ context: OverviewValuationContext,
        watchlistIDs: [String],
        portfolioLimit: Int = 25) -> [String] {
        let tokens = context.valuation().tokens
        let settings = context.settings
        let visible = Set(DashboardList(tokens, basis: .net, settings: settings, groupedBy: \.tokenId).visibleRows.map(\.key))
        let candidates = tokens.compactMap { token -> (id: String, priority: Decimal)? in
            guard
                let priceID = token.priceID,
                let priority = token.selectionValue,
                token.isCounted,
                isPolled(token, priceID: priceID, isVisible: visible.contains(token.tokenId), settings: settings)
            else { return nil }
            return (priceID, priority)
        }
        return rankedPollingIDs(candidates, watchlistIDs: watchlistIDs, portfolioLimit: portfolioLimit)
    }

    /// A token with a usable price is polled while the dashboard shows it. One without (valued from
    /// its sync value, or unpriced) is polled so it can get one, except, when `hideUnpriced` is on
    /// and the asset is not `alwaysShow`, an onchain ID whose sync value is dust under `hideDust`.
    private static func isPolled(
        _ token: ValuedToken,
        priceID: String,
        isVisible: Bool,
        settings: TokenDashboardSettings) -> Bool {
        switch token.source {
        case .manual, .live, .close:
            return isVisible
        case .sync, .unpriced:
            guard !token.alwaysShow, settings.hideUnpriced else { return true }
            guard OnchainTokenIdentity(historicalPriceID: priceID) != nil else { return true }
            return !settings.hideDust || abs(token.token.usdValue) >= settings.dustThresholdUSD
        case .ignored:
            return false
        }
    }

    /// Sums each ID's priorities, keeps the `portfolioLimit` largest (ties by first appearance), then
    /// appends the watchlist.
    private static func rankedPollingIDs(
        _ tokenCandidates: [(id: String, priority: Decimal)],
        watchlistIDs: [String],
        portfolioLimit: Int) -> [String] {
        var candidates: [String: PollingIDCandidate] = [:]
        for (insertionIndex, candidate) in tokenCandidates.enumerated() {
            upsertCandidate(
                id: candidate.id,
                priority: candidate.priority,
                insertionIndex: insertionIndex,
                candidates: &candidates)
        }

        var result = candidates.values.sorted {
            if $0.priority == $1.priority {
                return $0.firstIndex < $1.firstIndex
            }
            return $0.priority > $1.priority
        }
        .prefix(max(portfolioLimit, 0))
        .map(\.id)
        var seen = Set(result)

        for watchlistID in watchlistIDs {
            let normalizedID = normalizePollingID(watchlistID)
            guard !normalizedID.isEmpty, !seen.contains(normalizedID) else { continue }
            result.append(normalizedID)
            seen.insert(normalizedID)
        }

        return result
    }

    private struct PollingIDCandidate {
        var id: String
        var priority: Decimal
        var firstIndex: Int
    }

    private static func upsertCandidate(
        id: String,
        priority: Decimal,
        insertionIndex: Int,
        candidates: inout [String: PollingIDCandidate]) {
        let normalizedID = normalizePollingID(id)
        guard !normalizedID.isEmpty else { return }

        if var existing = candidates[normalizedID] {
            existing.priority += priority
            candidates[normalizedID] = existing
        } else {
            candidates[normalizedID] = PollingIDCandidate(
                id: normalizedID,
                priority: priority,
                firstIndex: insertionIndex)
        }
    }

    private static func normalizePollingID(_ id: String) -> String {
        OnchainTokenIdentity.normalizedHistoricalPriceID(id)
    }
}
