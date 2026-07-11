import Foundation
import PortuCore

extension PriceUpdate {
    func convertedUSDValues(to currency: FiatCurrency, rate: Decimal) -> PriceUpdate {
        guard currency != .usd else {
            return PriceUpdate(currency: .usd, prices: prices, changes24h: changes24h)
        }
        return PriceUpdate(
            currency: currency,
            prices: prices.mapValues { $0 * rate },
            // Zapper reports USD changes, which are invalid after FX conversion.
            changes24h: [:])
    }
}
