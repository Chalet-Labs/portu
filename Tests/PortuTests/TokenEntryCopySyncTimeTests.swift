import Foundation
@testable import Portu
import PortuCore
import Testing

struct TokenEntryCopySyncTimeTests {
    @Test func `token settings copy helper keeps the sync time`() {
        let syncedAt = Date(timeIntervalSince1970: 1_759_700_000)
        let token = TokenEntry(
            assetId: UUID(),
            symbol: "ETH",
            name: "Ethereum",
            category: .major,
            coinGeckoId: "ethereum",
            role: .balance,
            amount: 2,
            usdValue: 5000,
            syncedAt: syncedAt)

        let copy = TokenSettingsFeature.tokenEntry(from: token, coinGeckoId: "weth", usdValue: 4000)

        #expect(copy.syncedAt == syncedAt)
    }

    @Test func `manual price adjustment keeps the sync time`() {
        let syncedAt = Date(timeIntervalSince1970: 1_759_700_000)
        let token = TokenEntry(
            assetId: UUID(),
            symbol: "ETH",
            name: "Ethereum",
            category: .major,
            coinGeckoId: "ethereum",
            role: .balance,
            amount: 2,
            usdValue: 5000,
            syncedAt: syncedAt)
        let override = TokenPricingOverrideSnapshot(assetId: token.assetId, manualPriceUSD: 3000)

        let adjusted = TokenSettingsFeature.dashboardAdjustedToken(from: token, override: override)

        #expect(adjusted.usdValue == 6000)
        #expect(adjusted.syncedAt == syncedAt)
    }
}
