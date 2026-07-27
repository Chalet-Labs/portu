import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

@MainActor
struct AppFeatureIntervalTests {
    @Test func `scheduled provider sync uses provider intervals`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var syncedScopes: [PortfolioSyncScope] = []

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.providerSyncSettings.onchainPortfolioSyncInterval = { .seconds(10) }
            $0.providerSyncSettings.exchangePortfolioSyncInterval = { .seconds(21) }
            $0.syncEngine.syncScope = { scope in
                syncedScopes.append(scope)
                return SyncResult(failedAccounts: [])
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(9)
        await testClock.advance(by: .seconds(9))
        #expect(syncedScopes.isEmpty)

        now = now.addingTimeInterval(1)
        await testClock.advance(by: .seconds(1))
        await store.receive(.scheduledSyncDue(.onchain)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.onchain])

        now = now.addingTimeInterval(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(.scheduledSyncDue(.onchain)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.onchain, .onchain])

        now = now.addingTimeInterval(1)
        await testClock.advance(by: .seconds(1))
        await store.receive(.scheduledSyncDue(.exchange)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.onchain, .onchain, .exchange])

        await store.send(.stopScheduledSync)
    }

    @Test func `scheduled provider sync observes manual only changes after startup`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var onchainInterval: Duration?
        nonisolated(unsafe) var syncCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.providerSyncSettings.onchainPortfolioSyncInterval = { onchainInterval }
            $0.providerSyncSettings.exchangePortfolioSyncInterval = { nil }
            $0.syncEngine.syncScope = { scope in
                #expect(scope == .onchain)
                syncCount += 1
                return SyncResult(failedAccounts: [])
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(30)
        await testClock.advance(by: .seconds(30))
        #expect(syncCount == 0)

        onchainInterval = .seconds(10)
        now = now.addingTimeInterval(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(.scheduledSyncDue(.onchain)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncCount == 1)

        onchainInterval = nil
        now = now.addingTimeInterval(30)
        await testClock.advance(by: .seconds(30))
        #expect(syncCount == 1)

        await store.send(.stopScheduledSync)
    }

    @Test func `manual only scheduled sync starts no automatic provider loops`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var syncCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.providerSyncSettings.onchainPortfolioSyncInterval = { nil }
            $0.providerSyncSettings.exchangePortfolioSyncInterval = { nil }
            $0.syncEngine.syncScope = { _ in
                syncCount += 1
                return SyncResult(failedAccounts: [])
            }
            $0.continuousClock = testClock
            $0.currentDate.now = { now }
        }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(30)
        await testClock.advance(by: .seconds(30))
        #expect(syncCount == 0)
        await store.send(.stopScheduledSync)
    }

    @Test func `scheduled sync due skips while another sync is running`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var syncCount = 0

        let store = TestStore(
            initialState: AppFeature.State(syncStatus: .syncing(progress: 0.25))) {
                AppFeature()
            } withDependencies: {
                $0.providerSyncSettings.onchainPortfolioSyncInterval = { .seconds(5) }
                $0.providerSyncSettings.exchangePortfolioSyncInterval = { nil }
                $0.syncEngine.syncScope = { _ in
                    syncCount += 1
                    return SyncResult(failedAccounts: [])
                }
                $0.continuousClock = testClock
                $0.currentDate.now = { now }
            }

        await store.send(.startScheduledSync)
        now = now.addingTimeInterval(5)
        await testClock.advance(by: .seconds(5))
        await store.receive(.scheduledSyncDue(.onchain))
        #expect(syncCount == 0)

        await store.send(.stopScheduledSync)
    }
}
