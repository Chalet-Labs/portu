import Foundation
import PortuCore

/// What the page shows: the type and protocol picked in the sidebar.
struct AllPositionsFilter: Equatable {
    var type: PositionType?
    var protocolFilter: ProtocolFilter = .all

    static let all = AllPositionsFilter()

    func matches(_ card: AllPositionsCardInfo) -> Bool {
        if let type, card.positionType != type {
            return false
        }
        return protocolFilter.matches(card.protocolId)
    }
}

/// A position's card fields, read from the model once at the boundary.
struct AllPositionsCardInfo: Equatable, Identifiable, Sendable {
    let id: UUID
    let positionType: PositionType
    let protocolId: String?
    let protocolName: String?
    let chain: Chain?
    let healthFactor: Double?
}

/// The page as shown, money in the display currency. Sections and cards follow the filter; the
/// sidebar options cover every active position whatever is selected.
struct AllPositionsPage: Equatable {
    let sections: [AllPositionsSection]
    let typeOptions: [AllPositionsTypeOption]
    let protocolOptions: [AllPositionsProtocolOption]
}

struct AllPositionsSection: Equatable, Identifiable {
    let type: PositionType
    let title: String
    let total: Decimal
    let cards: [AllPositionsCard]

    var id: PositionType {
        type
    }
}

struct AllPositionsCard: Equatable, Identifiable {
    let id: UUID
    let title: String
    let chain: Chain?
    let healthFactor: Double?
    let total: Decimal
    let rows: [AllPositionsRow]
}

/// One token. `value` is the signed contribution of a counted row and the unsigned value of a
/// not-counted one; an unpriced or ignored row has none (U4).
struct AllPositionsRow: Equatable, Identifiable {
    let id: UUID
    let role: TokenRole
    let symbol: String
    let amount: Decimal
    let state: TokenRowState
    let value: Decimal?
}

struct AllPositionsTypeOption: Equatable, Identifiable {
    /// `nil` is "All".
    let type: PositionType?
    let label: String
    let total: Decimal

    var id: String {
        label
    }
}

struct AllPositionsProtocolOption: Equatable, Identifiable {
    let filter: ProtocolFilter
    let name: String
    let total: Decimal

    var id: ProtocolFilter {
        filter
    }
}

enum AllPositionsFormat {
    static func currency(_ value: Decimal, code: String) -> String {
        value.formatted(.currency(code: code))
    }

    static func amount(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2 ... 6)))
    }
}
