import Foundation
import PortuCore

extension TokenSettingsFeature {
    /// Forwarders to the PortuCore valuation layer until their callers use it directly.
    static func normalizedCoinGeckoID(_ id: String?) -> String? {
        TokenIdentityMappingFeature.normalizedProviderID(id)
    }

    static func sanitizedManualPrice(_ price: Decimal?) -> Decimal? {
        TokenPricingOverrideFeature.sanitizedManualPrice(price)
    }
}
