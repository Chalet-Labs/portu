import Foundation
@testable import Portu
import Testing

@MainActor
struct ProtocolFilterTests {
    // MARK: - Equality

    @Test func `all and none are distinct`() {
        #expect(ProtocolFilter.all != ProtocolFilter.none)
    }

    @Test func `specific matches by protocol id`() {
        #expect(ProtocolFilter.specific("aave") == ProtocolFilter.specific("aave"))
    }

    @Test func `specific does not equal all`() {
        #expect(ProtocolFilter.specific("aave") != ProtocolFilter.all)
    }

    @Test func `specific does not equal none`() {
        #expect(ProtocolFilter.specific("aave") != ProtocolFilter.none)
    }

    // MARK: - Filtering behavior

    private static let samplePositions: [(protocolId: String?, netUSDValue: Decimal)] = [
        (protocolId: "aave", netUSDValue: 1000),
        (protocolId: "uniswap", netUSDValue: 500),
        (protocolId: nil, netUSDValue: 250),
        (protocolId: "aave", netUSDValue: 300),
        (protocolId: nil, netUSDValue: 100)
    ]

    private func filtered(
        _ positions: [(protocolId: String?, netUSDValue: Decimal)],
        by filter: ProtocolFilter) -> [(protocolId: String?, netUSDValue: Decimal)] {
        positions.filter { pos in
            switch filter {
            case .all:
                true
            case .none:
                pos.protocolId == nil
            case let .specific(id):
                pos.protocolId == id
            }
        }
    }

    @Test func `all returns everything`() {
        let result = filtered(Self.samplePositions, by: .all)
        #expect(result.count == Self.samplePositions.count)
    }

    @Test func `none returns only positions without protocol`() {
        let result = filtered(Self.samplePositions, by: .none)
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.protocolId == nil })
    }

    @Test func `specific returns only matching protocol`() {
        let result = filtered(Self.samplePositions, by: .specific("aave"))
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.protocolId == "aave" })
    }
}
