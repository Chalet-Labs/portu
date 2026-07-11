import Foundation
@testable import Portu
import PortuCore
import Testing

struct PriceUpdateCurrencyTests {
    @Test func `converting usd fallback prices clears usd change percentages`() throws {
        let rate = try #require(Decimal(string: "0.92"))
        let expectedPrice = try #require(Decimal(string: "9.2"))
        let update = PriceUpdate(
            currency: .usd,
            prices: ["asset:base:0xtoken": 10],
            changes24h: ["asset:base:0xtoken": 0.05])

        let converted = update.convertedUSDValues(to: .eur, rate: rate)

        #expect(converted.currency == .eur)
        #expect(converted.prices["asset:base:0xtoken"] == expectedPrice)
        #expect(converted.changes24h.isEmpty)
    }
}
