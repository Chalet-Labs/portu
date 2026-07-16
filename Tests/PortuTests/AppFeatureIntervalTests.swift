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
            $0.providerSyncSettings.zapperPortfolioSyncInterval = { .seconds(10) }
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
        await store.receive(.scheduledSyncDue(.zapper)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.zapper])

        now = now.addingTimeInterval(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(.scheduledSyncDue(.zapper)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.zapper, .zapper])

        now = now.addingTimeInterval(1)
        await testClock.advance(by: .seconds(1))
        await store.receive(.scheduledSyncDue(.exchange)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncedScopes == [.zapper, .zapper, .exchange])

        await store.send(.stopScheduledSync)
    }

    @Test func `scheduled provider sync observes manual only changes after startup`() async {
        let testClock = TestClock()
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_000_000)
        nonisolated(unsafe) var zapperInterval: Duration?
        nonisolated(unsafe) var syncCount = 0

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.providerSyncSettings.zapperPortfolioSyncInterval = { zapperInterval }
            $0.providerSyncSettings.exchangePortfolioSyncInterval = { nil }
            $0.syncEngine.syncScope = { scope in
                #expect(scope == .zapper)
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

        zapperInterval = .seconds(10)
        now = now.addingTimeInterval(10)
        await testClock.advance(by: .seconds(10))
        await store.receive(.scheduledSyncDue(.zapper)) {
            $0.syncStatus = .syncing(progress: 0)
        }
        await store.receive(\.scheduledSyncCompleted) {
            $0.syncStatus = .idle
        }
        #expect(syncCount == 1)

        zapperInterval = nil
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
            $0.providerSyncSettings.zapperPortfolioSyncInterval = { nil }
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
                $0.providerSyncSettings.zapperPortfolioSyncInterval = { .seconds(5) }
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
        await store.receive(.scheduledSyncDue(.zapper))
        #expect(syncCount == 0)

        await store.send(.stopScheduledSync)
    }
}
