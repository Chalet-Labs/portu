import ComposableArchitecture
import Foundation
@testable import Portu
import Synchronization
import Testing

@MainActor
struct AppFeatureSyncProgressTests {
    typealias Trigger = AppFeatureSyncCompletionTests.Trigger

    private struct SyncFailed: Error, LocalizedError {
        var errorDescription: String? {
            "Network unavailable"
        }
    }

    enum Failure: CaseIterable, Sendable {
        case allAccountsFailed
        case network

        var error: any Error {
            switch self {
            case .allAccountsFailed: SyncError.allAccountsFailed
            case .network: SyncFailed()
            }
        }
    }

    @Test(arguments: Trigger.allCases)
    func `sync forwards each progress step before its completion`(_ trigger: Trigger) async {
        let accountID = UUID()
        let store = makeStore(reporting: [Self.halfway, Self.done]) {
            SyncResult(failedAccounts: [])
        }

        await store.send(trigger.startAction(accountID: accountID)) {
            $0.syncStatus = .syncing
            $0.syncingAccountID = trigger == .account ? accountID : nil
        }
        await store.receive(.syncProgressUpdated(0.5)) {
            $0.syncProgress = 0.5
        }
        await store.receive(.syncProgressUpdated(1)) {
            $0.syncProgress = 1
        }
        await store.receive(trigger.completionAction(.success(SyncResult(failedAccounts: [])))) {
            $0.syncStatus = .idle
            $0.syncingAccountID = nil
        }
    }

    @Test(arguments: Trigger.allCases, Failure.allCases)
    func `sync forwards progress before a failed completion`(_ trigger: Trigger, _ failure: Failure) async {
        let accountID = UUID()
        let store = makeStore(reporting: [Self.halfway]) {
            throw failure.error
        }

        await store.send(trigger.startAction(accountID: accountID)) {
            $0.syncStatus = .syncing
            $0.syncingAccountID = trigger == .account ? accountID : nil
        }
        await store.receive(.syncProgressUpdated(0.5)) {
            $0.syncProgress = 0.5
        }
        await store.receive(trigger.completionAction(.failure(SyncFailure(failure.error)))) {
            $0.syncingAccountID = nil
            switch (trigger, failure) {
            case (.account, .allAccountsFailed):
                // The account's row already shows its error.
                $0.syncStatus = .idle
            case (_, .allAccountsFailed):
                $0.syncStatus = .error(SyncError.allAccountsFailed.localizedDescription)
            case (_, .network):
                $0.syncStatus = .error("Network unavailable")
            }
        }
    }

    @Test(arguments: Trigger.allCases)
    func `a new sync starts its progress from zero`(_ trigger: Trigger) async {
        let accountID = UUID()
        let store = makeStore(reporting: [], initialState: AppFeature.State(syncProgress: 1)) {
            SyncResult(failedAccounts: [])
        }

        await store.send(trigger.startAction(accountID: accountID)) {
            $0.syncStatus = .syncing
            $0.syncProgress = 0
            $0.syncingAccountID = trigger == .account ? accountID : nil
        }
        await store.receive(trigger.completionAction(.success(SyncResult(failedAccounts: [])))) {
            $0.syncStatus = .idle
            $0.syncingAccountID = nil
        }
    }

    /// Views that only ask whether a sync is running read `syncStatus`; a progress step must not
    /// invalidate them, or every step re-renders whole pages.
    @Test func `progress does not notify observers of the sync status`() {
        let store = Store(initialState: AppFeature.State(syncStatus: .syncing)) {
            AppFeature()
        }
        let statusChanged = Mutex(false)
        withObservationTracking {
            _ = store.syncStatus
        } onChange: {
            statusChanged.withLock { $0 = true }
        }

        store.send(.syncProgressUpdated(0.5))

        #expect(store.syncProgress == 0.5)
        #expect(statusChanged.withLock { $0 } == false)

        // The observer is live: the completion does change the status.
        store.send(.syncCompleted(.success(SyncResult(failedAccounts: []))))
        #expect(statusChanged.withLock { $0 } == true)
    }

    @Test(arguments: [
        SyncStatus.idle,
        .completedWithErrors(failedAccounts: ["Binance"]),
        .error("Previous failure")
    ])
    func `progress arriving after the sync settled is ignored`(_ settledStatus: SyncStatus) async {
        let store = TestStore(initialState: AppFeature.State(syncStatus: settledStatus)) {
            AppFeature()
        }

        await store.send(.syncProgressUpdated(0.5))
    }

    @Test func `progress never moves backwards within a run`() async {
        let store = TestStore(initialState: AppFeature.State(syncStatus: .syncing, syncProgress: 0.5)) {
            AppFeature()
        }

        await store.send(.syncProgressUpdated(0.25))
        await store.send(.syncProgressUpdated(0.5))
        await store.send(.syncProgressUpdated(0.75)) {
            $0.syncProgress = 0.75
        }
    }

    private static let halfway = SyncProgress(completedSteps: 1, totalSteps: 2)
    private static let done = SyncProgress(completedSteps: 2, totalSteps: 2)

    /// A store whose engine reports `steps` from whichever sync runs, then finishes with `finish`.
    private func makeStore(
        reporting steps: [SyncProgress],
        initialState: AppFeature.State = AppFeature.State(),
        then finish: @escaping @Sendable () throws -> SyncResult) -> TestStoreOf<AppFeature> {
        let run: @Sendable (SyncProgressHandler) async throws -> SyncResult = { progress in
            for step in steps {
                await progress(step)
            }
            return try finish()
        }
        return TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.syncEngine = SyncEngineClient(
                sync: run,
                syncScope: { _, progress in try await run(progress) },
                syncAccount: { _, progress in try await run(progress) })
        }
    }
}
