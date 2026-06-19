import ComposableArchitecture
import Foundation
@testable import Portu
import Synchronization
import Testing

@MainActor
struct AppFeatureAccountSyncTests {
    @Test func `account sync happy path syncs requested account`() async {
        let accountID = UUID()
        let syncedAccountIDs = Mutex<[UUID]>([])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.syncAccount = { id in
                syncedAccountIDs.withLock { $0.append(id) }
                return SyncResult(failedAccounts: [])
            }
        }

        await store.send(.accountSyncTapped(accountID)) {
            $0.syncStatus = .syncing(progress: 0)
            $0.syncingAccountID = accountID
        }
        await store.receive(\.accountSyncCompleted) {
            $0.syncStatus = .idle
            $0.syncingAccountID = nil
        }
        #expect(syncedAccountIDs.withLock { $0 } == [accountID])
    }

    @Test func `row recorded account sync failure resets to idle without a global error`() async {
        let accountID = UUID()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.syncAccount = { _ in throw SyncError.allAccountsFailed }
        }

        await store.send(.accountSyncTapped(accountID)) {
            $0.syncStatus = .syncing(progress: 0)
            $0.syncingAccountID = accountID
        }
        // A single-account failure is surfaced on the row's lastSyncError, not as a
        // global error banner — global status returns to idle.
        await store.receive(\.accountSyncCompleted) {
            $0.syncStatus = .idle
            $0.syncingAccountID = nil
        }
    }

    @Test func `non row account sync failure surfaces global error`() async {
        struct SnapshotSaveFailed: Error, LocalizedError {
            var errorDescription: String? {
                "Snapshot save failed"
            }
        }

        let accountID = UUID()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.syncAccount = { _ in throw SnapshotSaveFailed() }
        }

        await store.send(.accountSyncTapped(accountID)) {
            $0.syncStatus = .syncing(progress: 0)
            $0.syncingAccountID = accountID
        }
        await store.receive(\.accountSyncCompleted) {
            $0.syncStatus = .error("Snapshot save failed")
            $0.syncingAccountID = nil
        }
    }

    @Test func `account sync guards against double tap`() async {
        let accountID = UUID()
        let syncingAccountID = UUID()
        let syncCount = Mutex(0)
        let store = TestStore(
            initialState: AppFeature.State(
                syncStatus: .syncing(progress: 0.5),
                syncingAccountID: syncingAccountID)) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.syncAccount = { _ in
                syncCount.withLock { $0 += 1 }
                return SyncResult(failedAccounts: [])
            }
        }

        await store.send(.accountSyncTapped(accountID))
        #expect(store.state.syncingAccountID == syncingAccountID)
        #expect(syncCount.withLock { $0 } == 0)
    }
}
