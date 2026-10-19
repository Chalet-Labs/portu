import Foundation
@testable import Portu
import Testing

struct OverviewPriceDisplayTests {
    @Test func `price display does not round tiny positive prices to zero`() throws {
        let price = try OverviewPriceDisplay.price(#require(Decimal(
            string: "0.0000000045",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(price == "$ <0.00000001")
    }

    @Test func `compact price display keeps constrained rows readable`() throws {
        let price = try OverviewPriceDisplay.compactPrice(#require(Decimal(
            string: "0.0000000045",
            locale: Locale(identifier: "en_US_POSIX"))))

        #expect(price == "$ <1e-8")
    }
}
