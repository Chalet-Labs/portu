import Foundation

/// Flat enum for account classification. No associated values — safe for SwiftData predicates.
/// Use `Account.exchangeType` and `Account.chain` for type-specific metadata.
public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case manual
    case exchange
    case wallet
}
