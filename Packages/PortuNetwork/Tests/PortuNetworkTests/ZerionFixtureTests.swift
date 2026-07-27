import Foundation
@testable import PortuNetwork
import Testing

struct ZerionFixtureTests {
    @Test func `sanitized captured positions fixture preserves native and grouped LP shapes`() throws {
        let envelope: ZerionCollectionEnvelope<ZerionPositionResource> = try decodeFixture(
            "positions-native-lp")

        #expect(envelope.data.count == 3)
        #expect(envelope.data.first?.attributes.quantity.numeric == "1.123456789012345678")
        #expect(envelope.data.first?.attributes.fungibleInfo?.implementations.first?.address == nil)
        #expect(envelope.data.dropFirst().map(\.attributes.groupID) == ["fixture-lp-group", "fixture-lp-group"])
    }

    @Test func `sanitized fungible fixture preserves percentage points and native implementation`() throws {
        let envelope: ZerionCollectionEnvelope<ZerionFungibleResource> = try decodeFixture("fungibles")

        #expect(envelope.data.first?.attributes.marketData?.changes?.percent1D == Decimal(string: "-4.25"))
        #expect(envelope.data.last?.attributes.implementations.first?.address == nil)
    }

    @Test func `sanitized chart fixture preserves second timestamps`() throws {
        let envelope: ZerionSingleEnvelope<ZerionChartResource> = try decodeFixture("chart-month")

        #expect(envelope.data.attributes.points.first?.timestamp == 1_784_937_600)
        #expect(envelope.data.attributes.points.count == 3)
    }

    private func decodeFixture<Value: Decodable>(_ name: String) throws -> Value {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json"))
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }
}
