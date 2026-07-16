import Foundation
import PortuCore

extension TokenSettingsFeature {
    private static let minimumPlausibleValueRatio = Decimal(string: "0.01", locale: Locale(identifier: "en_US_POSIX"))!
    private static let maximumPlausibleValueRatio = Decimal(100)

    static func tokenEntry(
        from token: TokenEntry,
        coinGeckoId: String?,
        onchainIdentity: OnchainTokenIdentity? = nil,
        preserveOnchainIdentity: Bool = true,
        amount: Decimal? = nil,
        usdValue: Decimal,
        logoURL: String? = nil) -> TokenEntry {
        TokenEntry(
            assetId: token.assetId,
            symbol: token.symbol,
            name: token.name,
            category: token.category,
            portfolioCategory: token.portfolioCategory,
            coinGeckoId: coinGeckoId,
            onchainIdentity: preserveOnchainIdentity ? (onchainIdentity ?? token.onchainIdentity) : onchainIdentity,
            role: token.role,
            amount: amount ?? token.amount,
            usdValue: usdValue,
            logoURL: logoURL ?? token.logoURL)
    }

    static func normalizedCoinGeckoID(_ id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func sanitizedManualPrice(_ price: Decimal?) -> Decimal? {
        guard let price, price > 0 else { return nil }
        return price
    }

    static func normalizedThreshold(_ value: Decimal) -> Decimal {
        value < 0 ? 0 : value
    }

    static func absolute(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    static func isPlausible(price: Decimal, priceID: String, token: TokenEntry) -> Bool {
        guard OnchainTokenIdentity(historicalPriceID: priceID) != nil else {
            return true
        }
        guard price > 0, token.amount != 0 else { return false }
        let referenceValue = absolute(token.usdValue)
        guard referenceValue > 0 else { return true }
        let impliedValue = absolute(token.amount * price)
        let ratio = impliedValue / referenceValue
        return ratio >= minimumPlausibleValueRatio && ratio <= maximumPlausibleValueRatio
    }

    static func resolvedPrice(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal? {
        if let manualPrice = sanitizedManualPrice(override?.manualPriceUSD) {
            return manualPrice
        }
        if
            let priceID = resolvedPriceID(token: token, override: override),
            let price = prices[priceID] {
            guard isPlausible(price: price, priceID: priceID, token: token) else {
                return nil
            }
            return price
        }
        return nil
    }

    static func resolvedValue(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?) -> Decimal? {
        guard token.amount != 0 else { return nil }
        guard let price = resolvedPrice(token: token, prices: prices, override: override) else { return nil }
        return token.amount * price
    }

    /// Settings-only price resolution. Mirrors `resolvedPrice` but converts the canonical-USD
    /// manual override into the display currency so it lines up with the already-display-currency
    /// live prices in the Settings table. Dashboard callers keep using `resolvedPrice` directly —
    /// its `prices` map is already in the display currency there, so no further conversion applies.
    static func resolvedDisplayPrice(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        usdToDisplayRate: Decimal) -> Decimal? {
        guard let price = resolvedPrice(token: token, prices: prices, override: override) else {
            return nil
        }
        guard sanitizedManualPrice(override?.manualPriceUSD) != nil else {
            return price
        }
        return price * usdToDisplayRate
    }

    static func resolvedDisplayValue(
        token: TokenEntry,
        prices: [String: Decimal],
        override: TokenPricingOverrideSnapshot?,
        usdToDisplayRate: Decimal) -> Decimal? {
        guard token.amount != 0 else { return nil }
        guard
            let price = resolvedDisplayPrice(
                token: token,
                prices: prices,
                override: override,
                usdToDisplayRate: usdToDisplayRate)
        else { return nil }
        return token.amount * price
    }
}
