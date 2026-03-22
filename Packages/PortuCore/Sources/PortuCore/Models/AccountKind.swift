import Foundation

/// Classifies the high-level shape of an account.
public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case wallet
    case exchange
    case manual
}
