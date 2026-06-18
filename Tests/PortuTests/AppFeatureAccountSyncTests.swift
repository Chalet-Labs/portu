import ComposableArchitecture
import Foundation
@testable import Portu
import PortuNetwork
import Testing

@MainActor
struct AppFeatureAccountSyncTests {
    @Test func `account sync happy path syncs requested account`() async {
        let accountID = UUID()
        nonisolated(unsafe) var syncedAccountIDs: [UUID] = []
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.syncAccount = { id in
                syncedAccountIDs.append(id)
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
        #expect(syncedAccountIDs == [accountID])
    }

    @Test func `account sync failure resets to idle without a global error`() async {
        struct AccountSyncFailed: Error, LocalizedError {
            var errorDescription: String? {
                "Account sync failed"
            }
        }

        let accountID = UUID()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.syncAccount = { _ in throw AccountSyncFailed() }
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

    @Test func `account sync guards against double tap`() async {
        let accountID = UUID()
        let syncingAccountID = UUID()
        nonisolated(unsafe) var syncCount = 0
        let store = TestStore(
            initialState: AppFeature.State(
                syncStatus: .syncing(progress: 0.5),
                syncingAccountID: syncingAccountID)) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.syncAccount = { _ in
                syncCount += 1
                return SyncResult(failedAccounts: [])
            }
        }

        await store.send(.accountSyncTapped(accountID))
        #expect(store.state.syncingAccountID == syncingAccountID)
        #expect(syncCount == 0)
    }
}
