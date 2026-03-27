import Foundation
import PortuCore

enum PositionFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case idle
    case lending
    case liquidityPool
    case staking
    case farming
    case vesting
    case other

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .idle:
            return "Idle"
        case .lending:
            return "Lending"
        case .liquidityPool:
            return "Liquidity Pool"
        case .staking:
            return "Staking"
        case .farming:
            return "Farming"
        case .vesting:
            return "Vesting"
        case .other:
            return "Other"
        }
    }

    func matches(_ position: Position) -> Bool {
        switch self {
        case .all:
            return true
        case .idle:
            return position.positionType == .idle
        case .lending:
            return position.positionType == .lending
        case .liquidityPool:
            return position.positionType == .liquidityPool
        case .staking:
            return position.positionType == .staking
        case .farming:
            return position.positionType == .farming
        case .vesting:
            return position.positionType == .vesting
        case .other:
            return position.positionType == .other
        }
    }
}
