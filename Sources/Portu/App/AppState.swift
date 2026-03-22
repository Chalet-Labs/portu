import Foundation
import PortuCore

enum SidebarSection: Hashable, Sendable {
    case overview
    case exposure
    case performance
    case allAssets
    case allPositions
    case accounts
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

@Observable
@MainActor
final class AppState {
    var selectedSection: SidebarSection = .overview
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]
    var priceChanges24h: [String: Decimal] = [:]
    var connectionStatus: ConnectionStatus = .idle
    var syncStatus: SyncStatus = .idle
    var storeIsEphemeral: Bool = false

    /// Set after ModelContainer is initialised in PortuApp.init()
    var syncEngine: SyncEngine?
}
