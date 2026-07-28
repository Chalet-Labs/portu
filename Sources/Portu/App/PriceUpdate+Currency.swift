import Foundation
import PortuCore

extension PriceUpdate {
    func convertedUSDValues(to currency: FiatCurrency, rate: Decimal, preserveChanges24h: Bool = false) -> PriceUpdate {
        // Canonical price updates are USD-priced; converting a non-USD update would
        // double-convert and drop valid 24h changes, so a non-USD source is a no-op.
        guard self.currency == .usd else { return self }
        guard currency != .usd else {
            return PriceUpdate(currency: .usd, prices: prices, changes24h: changes24h)
        }
        return PriceUpdate(
            currency: currency,
            prices: prices.mapValues { $0 * rate },
            // A percentage change is dimensionless, so it doesn't need scaling by
            // `rate` and stays valid after conversion. Provider fallback updates
            // opt in only when their change semantics have been normalized.
            changes24h: preserveChanges24h ? changes24h : [:])
    }
}
