import Foundation
import PortuCore

extension OverviewFeature {
    static func pricePollingIDs(
        tokens: [TokenEntry],
        prices: [String: Decimal] = [:],
        watchlistIDs: [String],
        overrides: [TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings = .defaults,
        portfolioLimit: Int = 25,
        usdToDisplayRate: Decimal = 1) -> [String] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        var candidates: [String: PollingIDCandidate] = [:]
        var insertionIndex = 0
        for token in tokens {
            let override = overrideMap[token.assetId]
            guard
                let priceID = pollingPriceID(
                    token: token,
                    prices: prices,
                    override: override,
                    settings: settings,
                    usdToDisplayRate: usdToDisplayRate)
            else { continue }
            upsertCandidate(
                id: priceID,
                priority: pollingPriority(
                    token: token,
                    prices: prices,
                    override: override,
                    fallbackUSDToDisplayRate: usdToDisplayRate),
                insertionIndex: insertionIndex,
                candidates: &candidates)
            insertionIndex += 1
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

    private static func pollingPriceID(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings,
        usdToDisplayRate: Decimal) -> String? {
        guard
            let priceID = TokenSettingsFeature.resolvedPriceID(
                token: token,
                override: override)
        else { return nil }

        if
            TokenSettingsFeature.isDashboardEligible(
                token: token,
                prices: prices,
                override: override,
                settings: settings,
                usdToDisplayRate: usdToDisplayRate) {
            return priceID
        }

        guard token.amount > 0 else { return nil }
        guard token.role.isPositive || token.role.isBorrow else { return nil }
        guard override?.isIgnored != true else { return nil }
        guard
            TokenSettingsFeature.resolvedValue(
                token: token,
                prices: prices,
                override: override) == nil
        else { return nil }
        if OnchainTokenIdentity(historicalPriceID: priceID) != nil {
            let threshold = normalizedThreshold(settings.minimumDashboardValue)
            guard threshold == 0 || absolute(token.usdValue) >= threshold || settings.hideDust == false else {
                return nil
            }
        }
        return priceID
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

    private static func pollingPriority(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        fallbackUSDToDisplayRate: Decimal) -> Decimal {
        let value = OverviewPositionPricing.tokenValue(
            token: token,
            prices: prices,
            override: override,
            fallbackUSDToDisplayRate: fallbackUSDToDisplayRate)
        return value == 0 ? absolute(token.usdValue * fallbackUSDToDisplayRate) : absolute(value)
    }

    private static func normalizedThreshold(_ value: Decimal) -> Decimal {
        value < 0 ? 0 : value
    }

    private static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
