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

        #expect(UpdateChannel.stable.rawValue == "stable")
        #expect(UpdateChannel.alpha.rawValue == "alpha")
        #expect(UpdateChannel.allCases == [.stable, .alpha])
    }

    @Test func `enabling automatic checks updates state and persists through updater client`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { UpdaterPreferences() }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updatePreferencesLoaded(UpdaterPreferences()))

        await store.send(.setAutomaticChecksEnabled(true)) {
            $0.updatePreferences.automaticallyChecksForUpdates = true
        }

        #expect(capturedAutomaticallyChecks == [true])
        #expect(capturedChannel == nil)
        #expect(!didCheckForUpdates)

        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `disabling automatic checks updates state and leaves manual checks functional`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()

        let initialPreferences = UpdaterPreferences(automaticallyChecksForUpdates: true, channel: .stable)
        let store = TestStore(initialState: AppFeature.State(updatePreferences: initialPreferences)) {
            AppFeature()
        } withDependencies: {
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
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()
        let storedPreferences = UpdaterPreferences(automaticallyChecksForUpdates: true, channel: .alpha)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { storedPreferences }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updatePreferencesLoaded(storedPreferences)) {
            $0.updatePreferences = storedPreferences
        }

        #expect(store.state.updatePreferences == storedPreferences)
        #expect(!didCheckForUpdates)
        #expect(capturedAutomaticallyChecks.isEmpty)
        #expect(capturedChannel == nil)

        preferenceStream.continuation.finish()
        await store.finish()
    }

    @Test func `external preference stream updates state without explicit reducer action`() async {
        nonisolated(unsafe) var didCheckForUpdates = false
        nonisolated(unsafe) var capturedAutomaticallyChecks: [Bool] = []
        nonisolated(unsafe) var capturedChannel: UpdateChannel?
        let preferenceStream = AsyncStream<UpdaterPreferences>.makeStream()
        let initialPreferences = UpdaterPreferences(automaticallyChecksForUpdates: false, channel: .stable)
        let updatedPreferences = UpdaterPreferences(automaticallyChecksForUpdates: true, channel: .stable)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.updater.checkForUpdates = { didCheckForUpdates = true }
            $0.updater.preferences = { initialPreferences }
            $0.updater.setAutomaticallyChecksForUpdates = { capturedAutomaticallyChecks.append($0) }
            $0.updater.setChannel = { capturedChannel = $0 }
            $0.updater.preferenceChanges = { preferenceStream.stream }
        }

        await store.send(.appLaunched)
        await store.receive(.updatePreferencesLoaded(initialPreferences))

        preferenceStream.continuation.yield(updatedPreferences)

        await store.receive(.updatePreferencesLoaded(updatedPreferences)) {
            $0.updatePreferences = updatedPreferences
        }

        #expect(store.state.updatePreferences.automaticallyChecksForUpdates == true)
        #expect(store.state.updatePreferences.channel == .stable)

        preferenceStream.continuation.finish()
        await store.finish()
    }
}
