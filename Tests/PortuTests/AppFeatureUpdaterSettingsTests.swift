import ComposableArchitecture
import Foundation
@testable import Portu
import PortuCore
import Testing

@MainActor
struct AppFeatureUpdaterSettingsTests {
    @Test func `updater preferences and channels have expected defaults and ordering`() {
        let defaultPreferences = UpdaterPreferences()
        #expect(defaultPreferences.automaticallyChecksForUpdates == false)
        #expect(defaultPreferences.channel == .stable)
        #expect(AppFeature.State().updatePreferences == defaultPreferences)
        // Default state must block manual checks until a live updater is confirmed
        #expect(!AppFeature.State().updaterStatus.canCheckForUpdates)

        #expect(UpdateChannel.stable.rawValue == "stable")
        #expect(UpdateChannel.alpha.rawValue == "alpha")
        #expect(UpdateChannel.allCases == [.stable, .alpha])
    }

    @Test func `enabling automatic checks updates state and persists through updater client`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.available)) {
            $0.updaterStatus = .available
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        await store.send(.setAutomaticChecksEnabled(true)) {
            $0.updatePreferences.automaticallyChecksForUpdates = true
        }

        #expect(capturedAutomaticallyChecks == [true])
        #expect(capturedChannel == nil)
        #expect(!didCheckForUpdates)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `disabling automatic checks updates state and leaves manual checks functional`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let initialPreferences = UpdaterPreferences(automaticallyChecksForUpdates: true, channel: .stable)
        var initialState = AppFeature.State()
        initialState.updatePreferences = initialPreferences
        // Pre-set available so checkForUpdatesTapped is not gated
        initialState.updaterStatus = .available

        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { initialPreferences }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.setAutomaticChecksEnabled(false)) {
            $0.updatePreferences.automaticallyChecksForUpdates = false
        }

        #expect(capturedAutomaticallyChecks == [false])

        await store.send(.checkForUpdatesTapped)
        #expect(didCheckForUpdates)

        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `changing update channel updates state and persists through updater client`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.setUpdateChannel(.alpha)) {
            $0.updatePreferences.channel = .alpha
        }
        #expect(capturedChannel == .alpha)

        await store.send(.setUpdateChannel(.stable)) {
            $0.updatePreferences.channel = .stable
        }
        #expect(capturedChannel == .stable)

        #expect(capturedAutomaticallyChecks.isEmpty)
        #expect(!didCheckForUpdates)

        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `launch loads stored updater preferences into state`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()
        let storedPreferences = UpdaterPreferences(automaticallyChecksForUpdates: true, channel: .alpha)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { storedPreferences }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.available)) {
            $0.updaterStatus = .available
        }
        await store.receive(.updatePreferencesLoaded(storedPreferences)) {
            $0.updatePreferences = storedPreferences
        }

        #expect(store.state.updaterStatus.canCheckForUpdates)
        #expect(store.state.updatePreferences == storedPreferences)
        #expect(!didCheckForUpdates)
        #expect(capturedAutomaticallyChecks.isEmpty)
        #expect(capturedChannel == nil)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `external preference stream updates state without explicit reducer action`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let statusStream = AsyncStream<UpdaterStatus>.makeStream()
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()
        let initialPreferences = UpdaterPreferences(automaticallyChecksForUpdates: false, channel: .stable)
        let updatedPreferences = UpdaterPreferences(automaticallyChecksForUpdates: true, channel: .stable)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { statusStream.stream }
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { initialPreferences }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.available)) {
            $0.updaterStatus = .available
        }
        await store.receive(.updatePreferencesLoaded(initialPreferences))

        preferenceStream.continuation.yield(updatedPreferences)

        await store.receive(.updatePreferencesLoaded(updatedPreferences)) {
            $0.updatePreferences = updatedPreferences
        }

        #expect(store.state.updatePreferences.automaticallyChecksForUpdates == true)
        #expect(store.state.updatePreferences.channel == .stable)

        statusStream.continuation.finish()
        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `launch marks settings unavailable when updater is disabled`() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .unavailable(reason: "Updates not available") }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.preferenceChanges = { AsyncStream { $0.finish() } }
        }

        await store.send(.appLaunched)
        await store.receive(.updaterStatusChanged(.unavailable(reason: "Updates not available"))) {
            $0.updaterStatus = .unavailable(reason: "Updates not available")
        }
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        #expect(!store.state.updaterStatus.canCheckForUpdates)
        await store.finish()
    }

    @Test func `rapid channel changes cancel stale write effects`() async {
        nonisolated(unsafe) var capturedChannels: [UpdateChannel] = []
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.status = { .available }
            $0.updater.statusChanges = { AsyncStream { $0.finish() } }
            $0.updater.preferences = { UpdaterPreferences() }
            // The Alpha write suspends long enough for the Stable selection to
            // cancel it; the Stable write commits instantly. Only .stable may land.
            $0.updater.setChannel = { channel in
                if channel == .alpha {
                    try? await Task.sleep(for: .seconds(3600))
                }
                guard !Task.isCancelled else { return }
                capturedChannels.append(channel)
            }
            $0.updater.preferenceChanges = { AsyncStream { $0.finish() } }
        }

        await store.send(.setUpdateChannel(.alpha)) {
            $0.updatePreferences.channel = .alpha
        }
        await store.send(.setUpdateChannel(.stable)) {
            $0.updatePreferences.channel = .stable
        }

        await store.finish()
        #expect(capturedChannels == [.stable])
    }
}
