import Foundation
@testable import Portu
import Testing

struct ManualPositionPricingTests {
    @Test func `usd display recovers the same value as the raw live price`() {
        let value = ManualPositionPricing.usdValue(
            amount: 2, override: nil, displayPrice: 10, usdToDisplayRate: 1)

        #expect(value == 20)
    }

    @Test func `non-usd display converts the display price back to usd`() throws {
        // 10 USD shown as 9.2 EUR at a 0.92 rate must persist as 20 USD, not 18.4.
        let rate = try #require(Decimal(string: "0.92"))
        let displayPrice = try #require(Decimal(string: "9.2"))

        let value = ManualPositionPricing.usdValue(
            amount: 2, override: nil, displayPrice: displayPrice, usdToDisplayRate: rate)

        #expect(value == 20)
    }

    @Test func `an override is treated as a usd amount and wins over the live price`() {
        let value = ManualPositionPricing.usdValue(
            amount: 2, override: 50, displayPrice: 9.2, usdToDisplayRate: 0.92)

        #expect(value == 50)
    }

    @Test func `no live price and no override yields zero`() {
        let value = ManualPositionPricing.usdValue(
            amount: 2, override: nil, displayPrice: nil, usdToDisplayRate: 0.92)

        #expect(value == 0)
    }

    @Test func `a non-positive rate falls back to zero instead of dividing`() {
        let value = ManualPositionPricing.usdValue(
            amount: 2, override: nil, displayPrice: 9.2, usdToDisplayRate: 0)

        #expect(value == 0)
    }
}
