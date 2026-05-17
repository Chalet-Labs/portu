import PortuCore
import PortuUI
import SwiftUI

struct OverviewTokenChange: Equatable {
    let token: TokenEntry
    let change: Decimal
}

enum OverviewPriceChangeFeature {
    static func portfolioChange24h(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot],
        settings: TokenDashboardSettings? = nil) -> Decimal {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        let mapped = mappedTokens(tokens, mappings: mappings, overrides: overrides)
        let changeTokens = settings.map {
            dashboardEligibleTokensForChanges(
                tokens: mapped,
                prices: prices,
                changes24h: changes24h,
                overrideMap: overrideMap,
                settings: $0)
        } ?? mapped

        return changeTokens.reduce(Decimal.zero) { total, token in
            total + signedChange24h(
                token: token,
                prices: prices,
                changes24h: changes24h,
                override: overrideMap[token.assetId])
        }
    }

    static func keyChangeTokens(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        overrides: [TokenPricingOverrideSnapshot],
        mappings: [TokenIdentityMappingSnapshot],
        limit: Int = 20) -> [OverviewTokenChange] {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        return mappedTokens(tokens, mappings: mappings, overrides: overrides)
            .filter(\.role.isPositive)
            .compactMap { token -> OverviewTokenChange? in
                let change = OverviewPositionPricing.change24h(
                    token: token,
                    prices: prices,
                    changes24h: changes24h,
                    override: overrideMap[token.assetId])
                guard change != 0 else { return nil }
                return OverviewTokenChange(token: token, change: change)
            }
            .sorted {
                let lhs = abs($0.change)
                let rhs = abs($1.change)
                if lhs == rhs {
                    return $0.token.symbol < $1.token.symbol
                }
                return lhs > rhs
            }
            .prefix(max(limit, 0))
            .map(\.self)
    }

    static func signedChange24h(
        token: TokenEntry,
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        let change = OverviewPositionPricing.change24h(
            token: token,
            prices: prices,
            changes24h: changes24h,
            override: override)
        if token.role.isBorrow {
            return -change
        }
        return token.role.isPositive ? change : 0
    }

    static func isDashboardEligibleForChange(
        token: TokenEntry,
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        settings: TokenDashboardSettings) -> Bool {
        guard token.amount > 0 else { return false }
        guard token.role.isPositive || token.role.isBorrow else { return false }
        guard override?.isIgnored != true else { return false }
        if override?.alwaysShow == true { return true }

        let value = OverviewPositionPricing.changeReferenceValue(
            token: token,
            prices: prices,
            changes24h: changes24h,
            override: override)
        if value == 0 {
            return !settings.hideUnpriced
        }
        if abs(value) < normalizedThreshold(settings.minimumDashboardValue) {
            return !settings.hideDust
        }
        return true
    }

    static func dashboardEligibleTokensForChanges(
        tokens: [TokenEntry],
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        overrideMap: [UUID: TokenPricingOverrideSnapshot],
        settings: TokenDashboardSettings) -> [TokenEntry] {
        tokens.filter { token in
            isDashboardEligibleForChange(
                token: token,
                prices: prices,
                changes24h: changes24h,
                override: overrideMap[token.assetId],
                settings: settings)
        }
    }

    private static func mappedTokens(
        _ tokens: [TokenEntry],
        mappings: [TokenIdentityMappingSnapshot],
        overrides: [TokenPricingOverrideSnapshot]) -> [TokenEntry] {
        TokenSettingsFeature.applyIdentityMappings(
            to: tokens,
            mappings: mappings,
            overrides: overrides)
    }
}

enum OverviewHistoricalPriceChangeFeature {
    static func queryStartDate(now: Date = .now) -> Date {
        HistoricalPriceCalendar.utcStartOfDay(for: now)
            .addingTimeInterval(-2 * 86400)
    }

    static func latestPrices(from prices: [HistoricalPriceEntry]) -> [String: Decimal] {
        var latestByID: [String: HistoricalLatestPrice] = [:]
        for price in prices {
            guard
                let id = normalizedHistoricalPriceID(price.coinGeckoId),
                price.usdPrice > 0
            else { continue }
            let day = HistoricalPriceCalendar.utcStartOfDay(for: price.day)
            guard let existing = latestByID[id] else {
                latestByID[id] = HistoricalLatestPrice(day: day, price: price.usdPrice)
                continue
            }
            if day > existing.day || (day == existing.day && price.usdPrice > existing.price) {
                latestByID[id] = HistoricalLatestPrice(day: day, price: price.usdPrice)
            }
        }
        return latestByID.mapValues(\.price)
    }

    static func mergedPrices(
        live: [String: Decimal],
        historical: [String: Decimal]) -> [String: Decimal] {
        var merged: [String: Decimal] = [:]
        for (id, price) in historical where price > 0 {
            guard let normalizedID = normalizedHistoricalPriceID(id) else { continue }
            merged[normalizedID] = price
        }
        for (id, price) in live where price > 0 {
            guard let normalizedID = normalizedHistoricalPriceID(id) else { continue }
            merged[normalizedID] = price
        }
        return merged
    }

    static func changes24h(from prices: [HistoricalPriceEntry]) -> [String: Decimal] {
        var latestPairs: [String: HistoricalPriceChangePair] = [:]
        for price in prices {
            guard
                let id = normalizedHistoricalPriceID(price.coinGeckoId),
                price.usdPrice > 0
            else { continue }
            let day = HistoricalPriceCalendar.utcStartOfDay(for: price.day)
            latestPairs[id, default: HistoricalPriceChangePair()]
                .update(day: day, price: price.usdPrice)
        }

        var changes: [String: Decimal] = [:]
        for (id, pair) in latestPairs {
            guard
                let latestPrice = pair.latestPrice,
                let previousPrice = pair.previousPrice,
                previousPrice > 0
            else { continue }
            changes[id] = (latestPrice - previousPrice) / previousPrice
        }
        return changes
    }

    static func mergedChanges24h(
        live: [String: Decimal],
        historical: [String: Decimal]) -> [String: Decimal] {
        var merged: [String: Decimal] = [:]
        for (id, change) in historical {
            guard let normalizedID = normalizedHistoricalPriceID(id) else { continue }
            merged[normalizedID] = change
        }
        for (id, change) in live {
            guard let normalizedID = normalizedHistoricalPriceID(id) else { continue }
            merged[normalizedID] = change
        }
        return merged
    }

    private static func normalizedHistoricalPriceID(_ id: String?) -> String? {
        TokenIdentityMappingFeature.normalizedHistoricalPriceID(id)
    }
}

private struct HistoricalLatestPrice {
    var day: Date
    var price: Decimal
}

private struct HistoricalPriceChangePair {
    var latestDay: Date?
    var latestPrice: Decimal?
    var previousDay: Date?
    var previousPrice: Decimal?

    mutating func update(day: Date, price: Decimal) {
        guard let currentLatestDay = latestDay else {
            latestDay = day
            latestPrice = price
            return
        }

        if day > currentLatestDay {
            previousDay = currentLatestDay
            previousPrice = latestPrice
            latestDay = day
            latestPrice = price
        } else if day == currentLatestDay {
            latestPrice = price
        } else if previousDay == nil || day > previousDay! {
            previousDay = day
            previousPrice = price
        } else if day == previousDay {
            previousPrice = price
        }
    }
}

enum OverviewPositionPricing {
    private static let minimumPlausibleValueRatio = Decimal(string: "0.01", locale: Locale(identifier: "en_US_POSIX"))!
    private static let maximumPlausibleValueRatio = Decimal(100)

    static func price(
        coinGeckoId: String?,
        amount _: Decimal,
        usdValue _: Decimal,
        prices: [String: Decimal]) -> Decimal {
        normalizedPrice(coinGeckoId: coinGeckoId, prices: prices) ?? 0
    }

    static func tokenValue(
        coinGeckoId: String?,
        amount: Decimal,
        usdValue _: Decimal,
        prices: [String: Decimal]) -> Decimal {
        normalizedPrice(coinGeckoId: coinGeckoId, prices: prices).map { amount * $0 } ?? 0
    }

    static func price(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        if let manualPrice = override?.manualPriceUSD, manualPrice > 0 {
            return manualPrice
        }
        guard let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override) else {
            return 0
        }
        guard let price = prices[priceID] else {
            return 0
        }
        if OnchainTokenIdentity(historicalPriceID: priceID) == nil || isPlausible(price: price, amount: token.amount, usdValue: token.usdValue) {
            return price
        }
        return 0
    }

    static func tokenValue(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        if let manualPrice = override?.manualPriceUSD, manualPrice > 0 {
            return token.amount * manualPrice
        }
        guard let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override) else {
            return 0
        }
        guard let price = prices[priceID] else {
            return 0
        }
        if OnchainTokenIdentity(historicalPriceID: priceID) == nil || isPlausible(price: price, amount: token.amount, usdValue: token.usdValue) {
            return token.amount * price
        }
        return 0
    }

    static func change24h(
        coinGeckoId: String?,
        amount: Decimal,
        prices: [String: Decimal],
        changes24h: [String: Decimal]) -> Decimal {
        guard
            let coinGeckoId = OverviewWatchlistStore.normalizedID(coinGeckoId),
            let price = prices[coinGeckoId],
            let changePercent = changes24h[coinGeckoId]
        else {
            return 0
        }
        return amount * price * changePercent
    }

    static func change24h(
        token: TokenEntry,
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        if let manualPrice = override?.manualPriceUSD, manualPrice > 0 {
            return 0
        }
        guard
            let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override),
            let changePercent = changes24h[priceID]
        else {
            return 0
        }
        return changeReferenceValue(
            token: token,
            prices: prices,
            changes24h: changes24h,
            override: override) * changePercent
    }

    static func changeReferenceValue(
        token: TokenEntry,
        prices: [String: Decimal],
        changes24h: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        if let manualPrice = override?.manualPriceUSD, manualPrice > 0 {
            return 0
        }
        guard
            let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override),
            changes24h[priceID] != nil
        else {
            return 0
        }

        if prices[priceID] != nil {
            return tokenValue(token: token, prices: prices, override: override)
        }
        return token.usdValue > 0 ? token.usdValue : 0
    }

    static func isPlausible(
        price: Decimal,
        amount: Decimal,
        usdValue: Decimal) -> Bool {
        guard price > 0, amount > 0 else { return false }
        let referenceValue = abs(usdValue)
        guard referenceValue > 0 else { return true }
        let impliedValue = abs(amount * price)
        let ratio = impliedValue / referenceValue
        return ratio >= minimumPlausibleValueRatio && ratio <= maximumPlausibleValueRatio
    }

    private static func normalizedPrice(
        coinGeckoId: String?,
        prices: [String: Decimal]) -> Decimal? {
        OverviewWatchlistStore.normalizedID(coinGeckoId).flatMap { prices[$0] }
    }
}

private func normalizedThreshold(_ value: Decimal) -> Decimal {
    value < 0 ? 0 : value
}

enum OverviewPositionChangeTone: Equatable {
    case favorable
    case unfavorable

    static func tone(for role: TokenRole, change: Decimal) -> OverviewPositionChangeTone {
        if role.isBorrow {
            return change <= 0 ? .favorable : .unfavorable
        }
        return change >= 0 ? .favorable : .unfavorable
    }

    @MainActor
    var color: Color {
        switch self {
        case .favorable:
            PortuTheme.dashboardSuccess
        case .unfavorable:
            PortuTheme.dashboardWarning
        }
    }
}
