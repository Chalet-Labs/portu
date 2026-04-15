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

    #if DEBUG
        var debugServer: DebugServer?
    #endif

    /// Syncs all TCA state fields from the store; does not touch `onSyncRequested`.
    /// Guards each assignment to avoid redundant Observation notifications.
    func bridge(from store: StoreOf<AppFeature>) {
        updateIfChanged(\.prices, to: store.prices)
        updateIfChanged(\.priceChanges24h, to: store.priceChanges24h)
        updateIfChanged(\.syncStatus, to: store.syncStatus)
        updateIfChanged(\.connectionStatus, to: store.connectionStatus)
        updateIfChanged(\.lastPriceUpdate, to: store.lastPriceUpdate)
        updateIfChanged(\.storeIsEphemeral, to: store.storeIsEphemeral)
    }

    private func updateIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppState, Value>,
        to newValue: Value) {
        guard self[keyPath: keyPath] != newValue else { return }
        self[keyPath: keyPath] = newValue
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
