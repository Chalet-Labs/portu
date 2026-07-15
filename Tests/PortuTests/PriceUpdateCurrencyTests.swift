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

    @Test func `converting with preserveChanges24h keeps change percentages`() throws {
        let rate = try #require(Decimal(string: "0.92"))
        let expectedPrice = try #require(Decimal(string: "9.2"))
        let update = PriceUpdate(
            currency: .usd,
            prices: ["bitcoin": 10],
            changes24h: ["bitcoin": 0.05])

        let converted = update.convertedUSDValues(to: .eur, rate: rate, preserveChanges24h: true)

        #expect(converted.currency == .eur)
        #expect(converted.prices["bitcoin"] == expectedPrice)
        #expect(converted.changes24h == ["bitcoin": 0.05])
    }

    @Test func `converting a non-usd update is a no-op that preserves prices and changes`() throws {
        let rate = try #require(Decimal(string: "0.92"))
        let update = PriceUpdate(
            currency: .eur,
            prices: ["asset:base:0xtoken": 9.2],
            changes24h: ["asset:base:0xtoken": 0.05])

        let converted = update.convertedUSDValues(to: .eur, rate: rate)

        #expect(converted.currency == .eur)
        #expect(converted.prices["asset:base:0xtoken"] == update.prices["asset:base:0xtoken"])
        #expect(converted.changes24h == update.changes24h)
    }
}
