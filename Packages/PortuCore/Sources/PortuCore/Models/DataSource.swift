import Foundation

/// Identifies the provider family that owns an account's data.
public enum DataSource: String, Codable, CaseIterable, Sendable {
    case zapper
    case exchange
    case manual
}
