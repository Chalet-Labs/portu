import ComposableArchitecture
import Foundation
@testable import Portu
import Synchronization
import Testing

/// Pins every sync-completion transition and start guard, so the three
/// completion actions can share one implementation without state drifting.
@MainActor
struct AppFeatureSyncCompletionTests {
    private struct SyncFailed: Error, LocalizedError {
        var errorDescription: String? {
            "Network unavailable"
        }
    }

    enum Trigger: CaseIterable, Sendable {
        case manual
        case account
        case scheduled

        func startAction(accountID: UUID) -> AppFeature.Action {
            switch self {
            case .manual: .syncTapped
            case .account: .accountSyncTapped(accountID)
            case .scheduled: .scheduledSyncDue(.onchain)
            }
        }

        func completionAction(_ result: Result<SyncResult, SyncFailure>) -> AppFeature.Action {
            switch self {
            case .manual: .syncCompleted(result)
            case .account: .accountSyncCompleted(result)
            case .scheduled: .scheduledSyncCompleted(result)
            }
        }
    }

    enum Outcome: CaseIterable, Sendable {
        case success
        case partial
        case failure
        case allAccountsFailed
        case otherSyncError

        var result: Result<SyncResult, SyncFailure> {
            switch self {
            case .success: .success(SyncResult(failedAccounts: []))
            case .partial: .success(SyncResult(failedAccounts: ["Binance", "Kraken"]))
            case .failure: .failure(SyncFailure(SyncFailed()))
            case .allAccountsFailed: .failure(SyncFailure(SyncError.allAccountsFailed))
            case .otherSyncError: .failure(SyncFailure(SyncError.accountNotFound))
            }
        }
    }

    // MARK: - Completion

    /// Written out per case rather than derived, so it cannot share a bug with the reducer.
    private static func expectedStatus(_ trigger: Trigger, _ outcome: Outcome) -> SyncStatus {
        switch (trigger, outcome) {
        case (_, .success):
            .idle
        case (_, .partial):
            .completedWithErrors(failedAccounts: ["Binance", "Kraken"])
        case (_, .failure):
            .error("Network unavailable")
        case (.account, .allAccountsFailed):
            // The row already carries the account's error, so the global banner stays clear.
            .idle
        case (.manual, .allAccountsFailed), (.scheduled, .allAccountsFailed):
            .error(SyncError.allAccountsFailed.localizedDescription)
        case (_, .otherSyncError):
            // Only `allAccountsFailed` is special; any other sync error still surfaces globally.
            .error(SyncError.accountNotFound.localizedDescription)
        }
    }

    @Test(arguments: Trigger.allCases, Outcome.allCases)
    func `completion resets the account marker and sets the established status`(
        _ trigger: Trigger,
        _ outcome: Outcome) async {
        let store = TestStore(
            initialState: AppFeature.State(
                syncStatus: .syncing(progress: 0.5),
                syncingAccountID: UUID())) {
            AppFeature()
        }

        await store.send(trigger.completionAction(outcome.result)) {
            $0.syncingAccountID = nil
            $0.syncStatus = Self.expectedStatus(trigger, outcome)
        }
    }

    // MARK: - Start guards

    @Test(arguments: Trigger.allCases)
    func `start trigger is ignored while a sync is running`(_ trigger: Trigger) async {
        let engineCalls = Mutex(0)
        let runningAccountID = UUID()
        let store = TestStore(
            initialState: AppFeature.State(
                syncStatus: .syncing(progress: 0.5),
                syncingAccountID: runningAccountID)) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine.sync = {
                engineCalls.withLock { $0 += 1 }
                return SyncResult(failedAccounts: [])
            }
            $0.syncEngine.syncScope = { _ in
                engineCalls.withLock { $0 += 1 }
                return SyncResult(failedAccounts: [])
            }
            $0.syncEngine.syncAccount = { _ in
                engineCalls.withLock { $0 += 1 }
                return SyncResult(failedAccounts: [])
            }
        }

        await store.send(trigger.startAction(accountID: UUID()))

        #expect(store.state.syncStatus == .syncing(progress: 0.5))
        #expect(store.state.syncingAccountID == runningAccountID)
        #expect(engineCalls.withLock { $0 } == 0)
    }

    /// Only `.syncing` blocks a new sync; a previous error or partial result must not.
    @Test(arguments: Trigger.allCases, [
        SyncStatus.idle,
        .error("Previous failure"),
        .completedWithErrors(failedAccounts: ["Binance"])
    ])
    func `start trigger begins a sync from any settled status`(
        _ trigger: Trigger,
        _ settledStatus: SyncStatus) async {
        let accountID = UUID()
        let store = TestStore(initialState: AppFeature.State(syncStatus: settledStatus)) {
            AppFeature()
        }

        await store.send(trigger.startAction(accountID: accountID)) {
            $0.syncStatus = .syncing(progress: 0)
            $0.syncingAccountID = trigger == .account ? accountID : nil
        }
        switch trigger {
        case .manual:
            await store.receive(\.syncCompleted) {
                $0.syncStatus = .idle
            }
        case .account:
            await store.receive(\.accountSyncCompleted) {
                $0.syncStatus = .idle
                $0.syncingAccountID = nil
            }
        case .scheduled:
            await store.receive(\.scheduledSyncCompleted) {
                $0.syncStatus = .idle
            }
        }
    }
}
