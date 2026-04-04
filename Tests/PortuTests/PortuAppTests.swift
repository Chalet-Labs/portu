import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - AppState Bridge Tests

// Tests for centralized TCA → AppState bridge.
//
// Bug #16: The bridge is currently scattered across per-window .onAppear/.onChange
// view modifiers in WindowGroup body. Each Cmd+N window duplicates the bridge,
// and the Settings scene has no bridge at all.
//
// These tests verify that AppState exposes a `bridge(from:)` method that:
// - Syncs all 6 TCA state fields to AppState in one call
// - Preserves existing callbacks (onSyncRequested)
// - Is idempotent (safe to call multiple times)

@MainActor
struct AppStateBridgeTests {
    @Test func `bridge syncs all fields from store to AppState`() {
        let store = Store(initialState: AppFeature.State(
            syncStatus: .syncing(progress: 0.5),
            connectionStatus: .fetching,
            prices: ["bitcoin": 50000],
            priceChanges24h: ["bitcoin": 2.5],
            lastPriceUpdate: Date(timeIntervalSince1970: 1_000_000),
            storeIsEphemeral: true)) {
                AppFeature()
            } withDependencies: {
                $0.syncEngine = .testValue
                $0.priceService = .testValue
            }

        let appState = AppState()
        appState.bridge(from: store)

        #expect(appState.prices == ["bitcoin": 50000])
        #expect(appState.priceChanges24h == ["bitcoin": 2.5])
        #expect(appState.syncStatus == .syncing(progress: 0.5))
        #expect(appState.connectionStatus == .fetching)
        #expect(appState.lastPriceUpdate == Date(timeIntervalSince1970: 1_000_000))
        #expect(appState.storeIsEphemeral == true)
    }

    @Test func `bridge preserves onSyncRequested callback`() {
        let store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine = .testValue
            $0.priceService = .testValue
        }

        var callbackInvoked = false
        let appState = AppState()
        appState.onSyncRequested = { callbackInvoked = true }

        appState.bridge(from: store)

        appState.onSyncRequested?()
        #expect(callbackInvoked)
    }

    @Test func `bridge is idempotent`() {
        let store = Store(initialState: AppFeature.State(
            prices: ["ethereum": 3000])) {
                AppFeature()
            } withDependencies: {
                $0.syncEngine = .testValue
                $0.priceService = .testValue
            }

        let appState = AppState()
        appState.bridge(from: store)
        appState.bridge(from: store)

        #expect(appState.prices == ["ethereum": 3000])
    }

    @Test func `bridge syncs default idle state`() {
        let store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine = .testValue
            $0.priceService = .testValue
        }

        let appState = AppState()
        appState.bridge(from: store)

        #expect(appState.prices.isEmpty)
        #expect(appState.priceChanges24h.isEmpty)
        #expect(appState.syncStatus == .idle)
        #expect(appState.connectionStatus == .idle)
        #expect(appState.lastPriceUpdate == nil)
        #expect(appState.storeIsEphemeral == false)
    }

    @Test func `bridge propagates store changes after initial sync`() async {
        let store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine = .testValue
            $0.priceService = .testValue
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
        }

        let appState = AppState()
        appState.observe(store)

        #expect(appState.prices.isEmpty)

        // Mutate store state via action after observe was called
        store.send(.pricesReceived(PriceUpdate(prices: ["bitcoin": 50000], changes24h: ["bitcoin": 2.5])))

        // Yield to allow observation callbacks to fire
        await Task.yield()

        // Continuous observation should propagate this
        #expect(appState.prices == ["bitcoin": 50000])
        #expect(appState.priceChanges24h == ["bitcoin": 2.5])
    }

    @Test func `bridge propagates sync status changes`() async {
        let syncCompleted = AsyncStream<Void>.makeStream()
        let store = Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = {
                for await _ in syncCompleted.stream {
                    break
                }
                return SyncResult(failedAccounts: [])
            }
            $0.priceService = .testValue
        }

        let appState = AppState()
        appState.observe(store)

        #expect(appState.syncStatus == .idle)

        // Start sync — store status changes to .syncing
        store.send(.syncTapped)
        await Task.yield()

        // Continuous observation should propagate this
        #expect(appState.syncStatus == .syncing(progress: 0))

        // Clean up: complete the sync
        syncCompleted.continuation.finish()
    }
}
