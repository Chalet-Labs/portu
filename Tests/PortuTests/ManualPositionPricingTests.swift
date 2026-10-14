import Foundation
@testable import Portu
import PortuCore
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

/// The value the sheet stores for a new manual position (U1): a typed value as entered, else the
/// USD price × the amount. `appState.prices` holds ten times the USD book here, so a lookup in the
/// display book would store another number.
@MainActor
struct ManualPositionLivePriceTests {
    private func appState(currency: FiatCurrency, rate: Decimal) -> AppState {
        let appState = AppState()
        appState.selectedCurrency = currency
        appState.currentUSDToDisplayRate = rate
        appState.livePricesUSD = ["bitcoin": 50000]
        appState.prices = ["bitcoin": 500_000]
        return appState
    }

    @Test func `a non-USD user stores the USD price times the amount`() throws {
        let appState = try appState(currency: .chf, rate: #require(Decimal(string: "0.9")))

        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: "bitcoin", appState: appState) == 100_000)
    }

    @Test func `a USD user stores the USD price times the amount`() {
        let appState = appState(currency: .usd, rate: 1)

        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: "bitcoin", appState: appState) == 100_000)
    }

    @Test func `a mixed-case CoinGecko ID finds its live price`() {
        let appState = appState(currency: .usd, rate: 1)
        appState.prices = appState.livePricesUSD

        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: " Bitcoin ", appState: appState) == 100_000)
    }

    /// The typed field is "USD Value", formatted as USD: a total, stored as entered, never
    /// multiplied by the amount or converted at the rate.
    @Test func `a typed value is stored as entered`() throws {
        let appState = try appState(currency: .chf, rate: #require(Decimal(string: "0.9")))

        #expect(ManualPositionPricing.usdValue(amount: 2, override: 50, coinGeckoId: "bitcoin", appState: appState) == 50)
        #expect(ManualPositionPricing.usdValue(amount: 2, override: 0, coinGeckoId: "bitcoin", appState: appState) == 0)
    }

    @Test func `no live price and no typed value stores zero`() {
        let appState = appState(currency: .usd, rate: 1)

        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: "unknown", appState: appState) == 0)
        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: nil, appState: appState) == 0)
    }
}

/// Add needs an account, an asset and an amount above 0 (U1).
struct ManualPositionEntryTests {
    @Test func `the Add button is enabled with an account, an asset and a positive amount`() {
        #expect(ManualPositionEntry.canAdd(hasAccount: true, hasAsset: true, amount: 1))
        #expect(!ManualPositionEntry.canAdd(hasAccount: false, hasAsset: true, amount: 1))
        #expect(!ManualPositionEntry.canAdd(hasAccount: true, hasAsset: false, amount: 1))
    }

    @Test func `the Add button is disabled at an amount of zero`() {
        #expect(!ManualPositionEntry.canAdd(hasAccount: true, hasAsset: true, amount: 0))
    }

    @Test func `the Add button is disabled at a negative amount`() {
        #expect(!ManualPositionEntry.canAdd(hasAccount: true, hasAsset: true, amount: -1))
    }
}
