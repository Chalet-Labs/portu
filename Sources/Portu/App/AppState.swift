import ComposableArchitecture
import Foundation
import PortuCore

enum SidebarSection: Hashable {
    case overview
    case exposure
    case performance
    case allAssets
    case allPositions
    case accounts
}

enum ConnectionStatus: Hashable {
    case idle
    case fetching
    case error(String)
}

enum SyncStatus: Hashable {
    case idle
    case syncing(progress: Double)
    case completedWithErrors(failedAccounts: [String])
    case error(String)
}

@Observable
@MainActor
final class AppState {
    var lastPriceUpdate: Date?
    var prices: [String: Decimal] = [:]
    var priceChanges24h: [String: Decimal] = [:]
    var connectionStatus: ConnectionStatus = .idle
    var syncStatus: SyncStatus = .idle
    var storeIsEphemeral: Bool = false

    /// Bridge: called by features to trigger sync until they're migrated to TCA (Phase 4)
    var onSyncRequested: (@MainActor () -> Void)?

    /// Syncs all TCA state fields from the store; does not touch `onSyncRequested`.
    func bridge(from store: StoreOf<AppFeature>) {
        prices = store.prices
        priceChanges24h = store.priceChanges24h
        syncStatus = store.syncStatus
        connectionStatus = store.connectionStatus
        lastPriceUpdate = store.lastPriceUpdate
        storeIsEphemeral = store.storeIsEphemeral
    }

    /// Continuously observes TCA store and syncs changes to AppState.
    /// Uses recursive `withObservationTracking` so this is centralized at app level,
    /// not duplicated per-window.
    func observe(_ store: StoreOf<AppFeature>) {
        withObservationTracking {
            bridge(from: store)
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observe(store)
            }
        }
    }
}
