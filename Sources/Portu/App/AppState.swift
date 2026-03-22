import Foundation
import SwiftData

/// Root transient UI state. Does NOT hold SwiftData model arrays.
/// Views use @Query directly for SwiftData collections.
@Observable
@MainActor
final class AppState {
    var selectedSection: SidebarSection = .overview
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]
    var priceChanges24h: [String: Decimal] = [:]
    var connectionStatus: ConnectionStatus = .idle
    var syncStatus: SyncStatus = .idle
}

enum SidebarSection: Hashable, Sendable {
    case overview
    case account(PersistentIdentifier)
}

enum ConnectionStatus: Hashable, Sendable {
    case idle
    case fetching
    case error(String)
}

enum SyncStatus: Hashable, Sendable {
    case idle
    case syncing(progress: Double)
    case completedWithErrors(failedAccounts: [String])
    case error(String)
}
