import Foundation
import SwiftData

/// Root transient UI state. Does NOT hold SwiftData model arrays.
/// Views use @Query directly for SwiftData collections.
@Observable
@MainActor
final class AppState {
    var selectedSection: SidebarSection = .portfolio
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]
    var connectionStatus: ConnectionStatus = .idle
}

enum SidebarSection: Hashable, Sendable {
    case portfolio
    case account(PersistentIdentifier)
}

enum ConnectionStatus: Hashable, Sendable {
    case idle
    case fetching
    case error(String)
}
