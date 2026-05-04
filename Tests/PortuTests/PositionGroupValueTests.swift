@testable import Portu
import PortuCore
import Testing

struct PositionGroupValueTests {
    @Test func `header total excludes rewards and signs borrows`() {
        let asset = Asset(
            symbol: "ETH",
            name: "Ethereum",
            coinGeckoId: "ethereum",
            category: .major)
        let tokens = [
            PositionToken(role: .supply, amount: 2, usdValue: 6000, asset: asset),
            PositionToken(role: .borrow, amount: 1, usdValue: 3000, asset: asset),
            PositionToken(role: .reward, amount: 10, usdValue: 500, asset: asset)
        ]

        let total = PositionGroupValue.headerTotal(for: tokens, livePrices: ["ethereum": 3100])

        #expect(total == 3100)
    }
}
