import Foundation
import PortuCore
import Testing

struct ValuationTypesSendableTests {
    @Test func `valuation inputs are sendable`() {
        requireSendable(TokenEntry.self)
        requireSendable(TokenDashboardSettings.self)
        requireSendable(TokenPricingOverrideSnapshot.self)
        requireSendable(TokenIdentityMappingSnapshot.self)
        requireSendable(HistoricalClose.self)
    }

    @Test func `historical close keeps its day and price`() {
        let day = Date(timeIntervalSince1970: 172_800)

        let close = HistoricalClose(day: day, price: 3)

        #expect(close.day == day)
        #expect(close.price == 3)
    }

    private func requireSendable(_: (some Sendable).Type) {}
}
