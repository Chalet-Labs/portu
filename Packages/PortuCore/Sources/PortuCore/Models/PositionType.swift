import Foundation

/// Classifies the operational shape of a position.
public enum PositionType: String, Codable, CaseIterable, Sendable {
    case idle
    case lending
    case liquidityPool
    case staking
    case farming
    case vesting
    case other
}
