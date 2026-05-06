import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// MARK: - AppState Bridge Tests

// Tests for the centralized TCA → AppState bridge/observation flow.
//
// Bug #16 was that the bridge used to be scattered across per-window
// .onAppear/.onChange view modifiers in the WindowGroup body, which duplicated
// bridging for each Cmd+N window and left the Settings scene without coverage.
//
// These tests verify the centralized AppState bridge behavior by checking that it:
// - Syncs all 6 TCA state fields to AppState in one call
// - Preserves existing callbacks (onSyncRequested)
// - Is idempotent (safe to call multiple times)
// - Continuously propagates store changes via observe(_:)

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

    @Test func `bridge propagates sync status changes`() async throws {
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

        // Continuous observation should propagate this
        try await waitForSyncStatus(.syncing(progress: 0), in: appState)

        // Clean up: complete the sync and wait for the in-flight effect
        syncCompleted.continuation.finish()

        try await waitForSyncStatus(.idle, in: appState)
    }

    private func waitForSyncStatus(
        _ expectedStatus: SyncStatus,
        in appState: AppState,
        timeout: Duration = .seconds(2)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while appState.syncStatus != expectedStatus, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(appState.syncStatus == expectedStatus)
    }
}
