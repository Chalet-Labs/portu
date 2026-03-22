import Foundation

/// Describes how a token contributes to a position's net value.
public enum TokenRole: String, Codable, CaseIterable, Sendable {
    case supply
    case borrow
    case reward
    case stake
    case lpToken
    case balance
}
