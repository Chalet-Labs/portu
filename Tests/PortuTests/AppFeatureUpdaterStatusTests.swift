import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

// Tests for the UpdaterStatus / UpdaterFailure / UpdaterClient contract (issue #83).
// Every async stream is explicitly finished so TestStore effects always conclude.

@MainActor
struct AppFeatureUpdaterStatusTests {
    // MARK: - UpdaterFailure contract

    @Test func `unavailable failure message contains canonical not-installed phrase`() {
        #expect(UpdaterFailure.unavailable.message.contains("The update was not installed"))
    }

    @Test func `validation failed message contains canonical not-installed phrase`() {
        #expect(UpdaterFailure.validationFailed.message.contains("The update was not installed"))
    }

    @Test func `recovery URL is the canonical GitHub releases page`() {
        #expect(UpdaterFailure.recoveryURL == URL(string: "https://github.com/Chalet-Labs/portu/releases")!)
    }

    // MARK: - Terminal cycle classification

    @Test func `successful cycle classifies as no failure`() {
        #expect(UpdaterFailure(terminalUpdateCycleError: nil) == nil)
    }

    @Test func `benign Sparkle outcomes classify as no failure`() {
        // SUNoUpdateError, SUInstallationCanceledError, SUInstallationAuthorizeLaterError
        for code in [1001, 4007, 4008] {
            let error = NSError(domain: "SUSparkleErrorDomain", code: code)
            #expect(UpdaterFailure(terminalUpdateCycleError: error) == nil)
        }
    }

    @Test func `signature and validation errors classify as validation failure`() {
        // SUSignatureError, SUValidationError
        for code in [3001, 3002] {
            let error = NSError(domain: "SUSparkleErrorDomain", code: code)
            #expect(UpdaterFailure(terminalUpdateCycleError: error) == .validationFailed)
        }
    }

    @Test func `other Sparkle errors classify as unavailable`() {
        // SUAppcastParseError, SUDownloadError, SUInstallationError
        for code in [1000, 2001, 4005] {
            let error = NSError(domain: "SUSparkleErrorDomain", code: code)
            #expect(UpdaterFailure(terminalUpdateCycleError: error) == .unavailable)
        }
    }

    @Test func `errors outside the Sparkle domain classify as unavailable`() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(UpdaterFailure(terminalUpdateCycleError: error) == .unavailable)
    }

    // MARK: - UpdaterStatus value-level

    @Test func `available status permits checks and carries no failure`() {
        let status = UpdaterStatus.available
        #expect(status.canCheckForUpdates)
        #expect(status.failure == nil)
    }

    @Test func `unavailable status blocks checks and carries no failure`() {
        let status = UpdaterStatus.unavailable(reason: "No feed configured")
        #expect(!status.canCheckForUpdates)
        #expect(status.failure == nil)
    }

    @Test func `externally managed status blocks checks and carries no failure`() {
        let status = UpdaterStatus.externallyManaged(owner: "Homebrew")
        #expect(!status.canCheckForUpdates)
        #expect(status.failure == nil)
    }

    @Test func `available status with embedded validation failure remains retryable`() {
        var status = UpdaterStatus.available
        status.failure = .validationFailed
        #expect(status.canCheckForUpdates)
        #expect(status.failure == .validationFailed)
    }

    @Test func `structural eligibility follows availability not the transient check flag`() {
        var status = UpdaterStatus.available
        status.canCheckForUpdates = false // dips while a session is in flight
        status.failure = .unavailable
        #expect(status.isUpdaterEligible)

        #expect(!UpdaterStatus.unavailable(reason: "No feed configured").isUpdaterEligible)
        #expect(!UpdaterStatus.externallyManaged(owner: "Homebrew").isUpdaterEligible)
    }

    @Test func `default app feature state updater status blocks checks with truthful copy`() {
        let status = AppFeature.State().updaterStatus
        #expect(!status.canCheckForUpdates)
        #expect(status.availability == .unavailable(reason: "Checking update availability…"))
    }

    // MARK: - Launch paths

    @Test func `launch stores unavailable status and blocks check for updates`() async {
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .unavailable(reason: "No feed configured") }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.unavailable(reason: "No feed configured"))) {
            $0.updaterStatus = .unavailable(reason: "No feed configured")
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        #expect(!store.state.updaterStatus.canCheckForUpdates)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `launch stores available status and permits check for updates`() async {
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.available)) {
            $0.updaterStatus = .available
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        #expect(store.state.updaterStatus.canCheckForUpdates)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `launch with externally managed status blocks check for updates`() async {
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .externallyManaged(owner: "Homebrew") }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.externallyManaged(owner: "Homebrew"))) {
            $0.updaterStatus = .externallyManaged(owner: "Homebrew")
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        #expect(!store.state.updaterStatus.canCheckForUpdates)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `immediately finished status stream concludes effects without blocking`() async {
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.available)) {
            $0.updaterStatus = .available
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        preferenceStream.continuation.finish()
        await store.finish()
    }

    // MARK: - Manual check gating

    @Test func `check for updates is suppressed when status is unavailable`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        var initialState = AppFeature.State()
        initialState.updaterStatus = .unavailable(reason: "No feed configured")

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.status = { .unavailable(reason: "No feed configured") }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { AsyncStream { $0.finish() } }
        }

        await store.send(.checkForUpdatesTapped)

        #expect(!didCheckForUpdates)
        await store.finish()
    }

    @Test func `check for updates fires when status is available`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        var initialState = AppFeature.State()
        initialState.updaterStatus = .available

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.status = { .available }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { AsyncStream { $0.finish() } }
        }

        await store.send(.checkForUpdatesTapped)

        #expect(didCheckForUpdates)
        await store.finish()
    }

    @Test func `check for updates is suppressed when externally managed`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        var initialState = AppFeature.State()
        initialState.updaterStatus = .externallyManaged(owner: "Homebrew")

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.status = { .externallyManaged(owner: "Homebrew") }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { AsyncStream { $0.finish() } }
        }

        await store.send(.checkForUpdatesTapped)

        #expect(!didCheckForUpdates)
        await store.finish()
    }

    // MARK: - Streamed status changes

    @Test func `streamed status change updates state and portfolio remains unchanged`() async {
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.available)) {
            $0.updaterStatus = .available
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        let assetsBefore = store.state.allAssets
        let accountsBefore = store.state.accounts

        statusStream.continuation.yield(.unavailable(reason: "Feed unreachable"))
        await store.receive(.updaterStatusChanged(.unavailable(reason: "Feed unreachable"))) {
            $0.updaterStatus = .unavailable(reason: "Feed unreachable")
        }

        // Portfolio and navigation state must be untouched by an updater status change
        #expect(store.state.allAssets == assetsBefore)
        #expect(store.state.accounts == accountsBefore)
        #expect(store.state.selectedSection == .overview)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    // MARK: - Failure overlay

    @Test func `validation failure streamed via status keeps availability for retry`() async {
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.available)) {
            $0.updaterStatus = .available
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        // Sparkle reports a validation failure: availability unchanged, failure overlaid
        var failedStatus = UpdaterStatus.available
        failedStatus.failure = .validationFailed
        statusStream.continuation.yield(failedStatus)
        await store.receive(.updaterStatusChanged(failedStatus)) {
            $0.updaterStatus = failedStatus
        }

        // Status is still available — failure is transient; retry is permitted
        #expect(store.state.updaterStatus.canCheckForUpdates)
        #expect(store.state.updaterStatus.failure == .validationFailed)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `dismiss validation failure clears it and leaves availability unchanged`() async {
        nonisolated(unsafe) var didDismiss = false
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        var initialState = AppFeature.State()
        initialState.updaterStatus = .available
        initialState.updaterStatus.failure = .validationFailed

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.dismissFailure = { didDismiss = true }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.dismissUpdaterFailure) {
            $0.updaterStatus.failure = nil
        }

        #expect(didDismiss)
        #expect(store.state.updaterStatus.canCheckForUpdates)
        #expect(store.state.updaterStatus.failure == nil)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `dismiss unavailable failure clears it and leaves availability unchanged`() async {
        nonisolated(unsafe) var didDismiss = false
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        var initialState = AppFeature.State()
        initialState.updaterStatus = .available
        initialState.updaterStatus.failure = .unavailable

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.dismissFailure = { didDismiss = true }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.dismissUpdaterFailure) {
            $0.updaterStatus.failure = nil
        }

        #expect(didDismiss)
        #expect(store.state.updaterStatus.failure == nil)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    // MARK: - Sparkle delegate wiring

    /// The delegate methods must keep the exact Objective-C selectors Sparkle
    /// looks up on its optional protocol; a signature drift would silently
    /// disable channel filtering or terminal-outcome reporting.
    @Test func `channel delegate responds to the Sparkle selectors it implements`() {
        let delegate = ChannelUpdaterDelegate()
        #expect(delegate.responds(
            to: #selector(ChannelUpdaterDelegate.allowedChannels(for:))))
        #expect(delegate.responds(
            to: #selector(ChannelUpdaterDelegate.updater(_:didFinishUpdateCycleFor:error:))))
    }
}
