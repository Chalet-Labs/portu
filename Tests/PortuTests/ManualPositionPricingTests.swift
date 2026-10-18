import Foundation
@testable import Portu
import PortuCore
import Testing

/// The value the sheet stores for a new manual position (U1): a typed value as entered, else the
/// USD price × the amount. The display currency and rate are not inputs.
struct ManualPositionPricingTests {
    private let livePricesUSD: [String: Decimal] = ["bitcoin": 50000]

    @Test func `the USD price times the amount is stored`() {
        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: "bitcoin", livePricesUSD: livePricesUSD) == 100_000)
    }

    @Test func `a mixed-case CoinGecko ID finds its live price`() {
        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: " Bitcoin ", livePricesUSD: livePricesUSD) == 100_000)
    }

    /// The typed field is "USD Value", formatted as USD: a total, stored as entered, never
    /// multiplied by the amount or converted at the rate.
    @Test func `a typed value is stored as entered`() {
        #expect(ManualPositionPricing.usdValue(amount: 2, override: 50, coinGeckoId: "bitcoin", livePricesUSD: livePricesUSD) == 50)
        #expect(ManualPositionPricing.usdValue(amount: 2, override: 0, coinGeckoId: "bitcoin", livePricesUSD: livePricesUSD) == 0)
    }

    @Test func `no live price and no typed value stores zero`() {
        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: "unknown", livePricesUSD: livePricesUSD) == 0)
        #expect(ManualPositionPricing.usdValue(amount: 2, override: nil, coinGeckoId: nil, livePricesUSD: livePricesUSD) == 0)
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

    // MARK: - The sheet's draft

    @Test func `an existing asset draft needs an account, a selected asset and a positive amount`() {
        #expect(draft())
        #expect(!draft(selectedAccountId: nil))
        #expect(!draft(selectedAssetId: nil))
        #expect(!draft(amount: 0))
        #expect(!draft(amount: -1))
    }

    @Test func `a new asset draft needs a symbol and a name, whatever asset is selected`() {
        #expect(draft(createNewAsset: true, newSymbol: "NEW", newName: "New Coin", selectedAssetId: nil))
        #expect(!draft(createNewAsset: true, newSymbol: "", newName: "New Coin"))
        #expect(!draft(createNewAsset: true, newSymbol: "NEW", newName: ""))
        #expect(!draft(createNewAsset: true, newSymbol: "NEW", newName: "New Coin", selectedAccountId: nil))
        #expect(!draft(createNewAsset: true, newSymbol: "NEW", newName: "New Coin", amount: 0))
        #expect(!draft(createNewAsset: true, newSymbol: "NEW", newName: "New Coin", amount: -1))
    }

    @Test func `an existing asset draft ignores the new asset fields`() {
        #expect(draft(newSymbol: "", newName: ""))
        #expect(!draft(newSymbol: "NEW", newName: "New Coin", selectedAssetId: nil))
    }

    /// A complete existing-asset draft, varied one field at a time.
    private func draft(
        createNewAsset: Bool = false,
        newSymbol: String = "",
        newName: String = "",
        selectedAccountId: UUID? = UUID(),
        selectedAssetId: UUID? = UUID(),
        amount: Decimal = 1) -> Bool {
        ManualPositionEntry.canAdd(
            selectedAccountId: selectedAccountId,
            createNewAsset: createNewAsset,
            newSymbol: newSymbol,
            newName: newName,
            selectedAssetId: selectedAssetId,
            amount: amount)
    }
}
