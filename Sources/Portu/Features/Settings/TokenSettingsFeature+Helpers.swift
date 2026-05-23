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
}
