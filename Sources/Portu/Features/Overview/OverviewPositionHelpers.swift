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
        mappings: [TokenIdentityMappingSnapshot]) -> Decimal {
        let overrideMap = TokenSettingsFeature.overridesByAssetId(overrides)
        return mappedTokens(tokens, mappings: mappings, overrides: overrides).reduce(Decimal.zero) { total, token in
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

enum OverviewPositionPricing {
    private static let minimumPlausibleValueRatio = Decimal(string: "0.01", locale: Locale(identifier: "en_US_POSIX"))!
    private static let maximumPlausibleValueRatio = Decimal(100)

    static func price(
        coinGeckoId: String?,
        amount: Decimal,
        usdValue: Decimal,
        prices: [String: Decimal]) -> Decimal {
        normalizedPrice(coinGeckoId: coinGeckoId, prices: prices)
            ?? (amount > 0 ? usdValue / amount : 0)
    }

    static func tokenValue(
        coinGeckoId: String?,
        amount: Decimal,
        usdValue: Decimal,
        prices: [String: Decimal]) -> Decimal {
        normalizedPrice(coinGeckoId: coinGeckoId, prices: prices).map { amount * $0 }
            ?? usdValue
    }

    static func price(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        if let manualPrice = override?.manualPriceUSD, manualPrice > 0 {
            return manualPrice
        }
        guard let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override) else {
            return localUnitPrice(amount: token.amount, usdValue: token.usdValue) ?? 0
        }
        guard let price = prices[priceID] else {
            return localUnitPrice(amount: token.amount, usdValue: token.usdValue) ?? 0
        }
        if OnchainTokenIdentity(historicalPriceID: priceID) == nil || isPlausible(price: price, amount: token.amount, usdValue: token.usdValue) {
            return price
        }
        return localUnitPrice(amount: token.amount, usdValue: token.usdValue) ?? price
    }

    static func tokenValue(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal {
        if let manualPrice = override?.manualPriceUSD, manualPrice > 0 {
            return token.amount * manualPrice
        }
        guard let priceID = TokenSettingsFeature.resolvedPriceID(token: token, override: override) else {
            return token.usdValue
        }
        guard let price = prices[priceID] else {
            return token.usdValue
        }
        if OnchainTokenIdentity(historicalPriceID: priceID) == nil || isPlausible(price: price, amount: token.amount, usdValue: token.usdValue) {
            return token.amount * price
        }
        return token.usdValue
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
        return tokenValue(token: token, prices: prices, override: override) * changePercent
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

    private static func localUnitPrice(amount: Decimal, usdValue: Decimal) -> Decimal? {
        guard amount > 0, usdValue > 0 else { return nil }
        return usdValue / amount
    }
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
