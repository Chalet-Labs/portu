import ComposableArchitecture
import Foundation
import Sparkle

struct UpdaterConfiguration: Equatable, Sendable {
    let feedURL: URL
    let publicKey: String

    init?(infoDictionary: [String: Any]) {
        guard
            let feedURLString = infoDictionary["SUFeedURL"] as? String,
            let feedURL = URL(string: feedURLString),
            feedURL.scheme == "https",
            let publicKey = infoDictionary["SUPublicEDKey"] as? String,
            Data(base64Encoded: publicKey)?.count == 32
        else {
            return nil
        }

        self.feedURL = feedURL
        self.publicKey = publicKey
    }

    init?(bundle: Bundle = .main) {
        guard let infoDictionary = bundle.infoDictionary else {
            return nil
        }
        self.init(infoDictionary: infoDictionary)
    }
}

/// Replay-then-live broadcaster shared by the preference and status streams:
/// every new subscriber first receives the latest committed value, then each
/// subsequent update, with strict per-stream ordering.
final class UpdaterBroadcaster<Value: Equatable & Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: Subscriber] = [:]
    private var latestValue: Value

    /// One delivery lock per subscriber so replay + updates for a single stream
    /// are strictly ordered, while independent subscribers never block each other.
    final class Subscriber {
        let continuation: AsyncStream<Value>.Continuation
        // Primed is written under the broadcaster's registry `lock` and read
        // under the same lock, so access is consistently synchronized.
        var primed = false
        let deliveryLock = NSLock()

        init(continuation: AsyncStream<Value>.Continuation) {
            self.continuation = continuation
        }

        func deliver(_ value: Value) {
            _ = deliveryLock.withLock {
                continuation.yield(value)
            }
        }

        /// Replays the registration snapshot, then — without releasing the
        /// delivery lock — primes the subscriber, re-reads the latest committed
        /// value via `readLatest`, and delivers any delta. Holding the lock
        /// across the whole sequence means update() (which acquires this same
        /// lock to yield) cannot interleave a newer delivery between the replay
        /// and the catch-up, so per-stream ordering is strict.
        func replayPrimeAndCatchUp(
            initial: Value,
            readLatest: () -> Value) {
            deliveryLock.lock()
            defer { deliveryLock.unlock() }
            continuation.yield(initial)
            let latest = readLatest()
            if latest != initial {
                continuation.yield(latest)
            }
        }
    }

    init(initialValue: Value) {
        self.latestValue = initialValue
    }

    func current() -> Value {
        lock.withLock {
            latestValue
        }
    }

    func update(_ value: Value) {
        // Deliver only to primed subscribers. A fresh subscriber registered
        // mid-flight misses this update, but its replay yields `latestValue` —
        // which already contains it — so nothing is lost and per-stream
        // ordering is preserved.
        let subscribersSnapshot: [Subscriber] = lock.withLock {
            latestValue = value
            return subscribers.values.filter(\.primed)
        }
        for subscriber in subscribersSnapshot {
            subscriber.deliver(value)
        }
    }

    func stream() -> AsyncStream<Value> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self, id] _ in
                self?.removeSubscriber(id: id)
            }
            let (subscriber, latest): (Subscriber, Value) = lock.withLock {
                let subscriber = Subscriber(continuation: continuation)
                subscribers[id] = subscriber
                return (subscriber, latestValue)
            }
            // Replay happens under the subscriber's delivery lock; priming and
            // the latest-value re-read happen inside readLatest under the
            // registry lock — the same lock update() uses to record new values
            // and filter primed subscribers. One synchronization domain for the
            // flag, and the delivery lock is held across the whole sequence so
            // nothing can interleave between replay and catch-up.
            subscriber.replayPrimeAndCatchUp(initial: latest) { [self] in
                lock.withLock {
                    subscriber.primed = true
                    return latestValue
                }
            }
        }
    }

    private func removeSubscriber(id: UUID) {
        lock.withLock {
            _ = subscribers.removeValue(forKey: id)
        }
    }
}

@MainActor
final class ChannelUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var preferencesProvider: (@MainActor () -> UpdaterPreferences)?
    /// Receives Sparkle's terminal outcome for every finished update cycle.
    /// `updater(_:didFinishUpdateCycleFor:error:)` is the only cycle callback
    /// this delegate listens to.
    var updateCycleFinished: (@MainActor ((any Error)?) -> Void)?

    @objc func allowedChannels(for _: SPUUpdater) -> Set<String> {
        let prefs = preferencesProvider?() ?? UpdaterPreferences()
        switch prefs.channel {
        case .stable:
            return []
        case .alpha:
            return ["alpha"]
        }
    }

    func updater(_: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error: (any Error)?) {
        updateCycleFinished?(error)
    }
}

@MainActor
final class SparkleUpdaterController {
    private let controller: SPUStandardUpdaterController
    private let delegate: ChannelUpdaterDelegate
    private let preferencesBroadcaster: UpdaterBroadcaster<UpdaterPreferences>
    private let statusBroadcaster: UpdaterBroadcaster<UpdaterStatus>
    private var automaticChecksObservation: NSKeyValueObservation?
    private var canCheckObservation: NSKeyValueObservation?
    private let userDefaults: UserDefaults

    static let channelKey = "portu.update.channel"

    init(configuration _: UpdaterConfiguration, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let savedChannelString = userDefaults.string(forKey: Self.channelKey)
        let initialChannel = savedChannelString.flatMap(UpdateChannel.init(rawValue:)) ?? .stable

        // Broadcaster and delegate provider are installed BEFORE startUpdater() so
        // the first update cycle already sees the saved channel; a stable fallback
        // during startup would hand an Alpha user stable-only results.
        //
        // The automatic-checks seed is read AFTER the SPUStandardUpdaterController
        // exists: Sparkle restores its SUEnableAutomaticChecks default into the
        // property at controller creation, and seeding from it keeps Settings in
        // sync with checks Sparkle has already scheduled.
        let delegate = ChannelUpdaterDelegate()
        self.delegate = delegate

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil)

        let initialPrefs = UpdaterPreferences(
            automaticallyChecksForUpdates: controller.updater.automaticallyChecksForUpdates,
            channel: initialChannel)
        let preferencesBroadcaster = UpdaterBroadcaster(initialValue: initialPrefs)
        self.preferencesBroadcaster = preferencesBroadcaster

        delegate.preferencesProvider = { [weak preferencesBroadcaster] in
            preferencesBroadcaster?.current() ?? UpdaterPreferences()
        }

        // Sparkle owns the SUEnableAutomaticChecks default (the native permission
        // prompt and Settings toggles both persist through it); never mirror it.
        controller.updater.automaticallyDownloadsUpdates = false
        controller.startUpdater()
        self.controller = controller

        // Seeded AFTER startUpdater() so the first status reflects the started
        // updater's real canCheckForUpdates. A controller only exists for a
        // resolved-available build, so availability here is always .available.
        let statusBroadcaster = UpdaterBroadcaster(initialValue: UpdaterStatus(
            availability: .available,
            canCheckForUpdates: controller.updater.canCheckForUpdates,
            failure: nil))
        self.statusBroadcaster = statusBroadcaster

        // Delegate callbacks and KVO both reach the main actor after init
        // returns, so installing these hooks after startUpdater() cannot miss
        // a terminal cycle.
        delegate.updateCycleFinished = { [weak self] error in
            self?.handleUpdateCycleFinished(error: error)
        }

        self.automaticChecksObservation = controller.updater.observe(
            \.automaticallyChecksForUpdates,
            options: [.new]) { [weak self] updater, _ in
                Task { @MainActor [weak self] in
                    self?.handleAutomaticChecksKVOChanged(updater.automaticallyChecksForUpdates)
                }
            }

        self.canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.new]) { [weak self] updater, _ in
                Task { @MainActor [weak self] in
                    self?.handleCanCheckKVOChanged(updater.canCheckForUpdates)
                }
            }
    }

    func checkForUpdates() {
        // A new check supersedes any previous failure; clear it as the check
        // starts so a stale notice never overlaps the fresh cycle's outcome.
        clearFailure()
        controller.checkForUpdates(nil)
    }

    func preferences() -> UpdaterPreferences {
        preferencesBroadcaster.current()
    }

    func status() -> UpdaterStatus {
        statusBroadcaster.current()
    }

    func dismissFailure() {
        clearFailure()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        // Assign unconditionally so Sparkle records the user's decision even when
        // the effective value is unchanged (declining an already-off prompt).
        controller.updater.automaticallyChecksForUpdates = enabled
        let current = preferencesBroadcaster.current()
        if current.automaticallyChecksForUpdates != enabled {
            let updated = UpdaterPreferences(
                automaticallyChecksForUpdates: enabled,
                channel: current.channel)
            preferencesBroadcaster.update(updated)
        }
    }

    // Serialization: both setters run on the main actor (as does Sparkle), so
    // writes commit one at a time in the order tasks reach it. The reducer's
    // cancel-in-flight ID supplies ordering — a newer selection cancels the
    // older effect before it can re-enter here.
    func setChannel(_ channel: UpdateChannel) {
        userDefaults.set(channel.rawValue, forKey: Self.channelKey)
        let current = preferencesBroadcaster.current()
        if current.channel != channel {
            let updated = UpdaterPreferences(
                automaticallyChecksForUpdates: current.automaticallyChecksForUpdates,
                channel: channel)
            preferencesBroadcaster.update(updated)
        }
    }

    nonisolated func preferenceChanges() -> AsyncStream<UpdaterPreferences> {
        preferencesBroadcaster.stream()
    }

    nonisolated func statusChanges() -> AsyncStream<UpdaterStatus> {
        statusBroadcaster.stream()
    }

    private func handleAutomaticChecksKVOChanged(_ enabled: Bool) {
        // The native prompt answered directly through Sparkle; just mirror the
        // observed value into the broadcast so TCA state cannot drift.
        let current = preferencesBroadcaster.current()
        if current.automaticallyChecksForUpdates != enabled {
            let updated = UpdaterPreferences(
                automaticallyChecksForUpdates: enabled,
                channel: current.channel)
            preferencesBroadcaster.update(updated)
        }
    }

    private func handleCanCheckKVOChanged(_ canCheck: Bool) {
        // Sparkle alone decides when checks are possible (it flips this during
        // in-flight sessions and back afterwards); mirror it into the status.
        var current = statusBroadcaster.current()
        if current.canCheckForUpdates != canCheck {
            current.canCheckForUpdates = canCheck
            statusBroadcaster.update(current)
        }
    }

    /// One terminal Sparkle callback yields at most one status broadcast: the
    /// cycle's classification — nil for success and for benign outcomes — is
    /// assigned unconditionally, so a clean cycle clears a stale failure and an
    /// unchanged value is never re-emitted.
    private func handleUpdateCycleFinished(error: (any Error)?) {
        let failure = UpdaterFailure(terminalUpdateCycleError: error)
        var current = statusBroadcaster.current()
        if current.failure != failure {
            current.failure = failure
            statusBroadcaster.update(current)
        }
    }

    private func clearFailure() {
        var current = statusBroadcaster.current()
        if current.failure != nil {
            current.failure = nil
            statusBroadcaster.update(current)
        }
    }
}

struct UpdaterClient: Sendable {
    var status: @Sendable () async -> UpdaterStatus
    var statusChanges: @Sendable () -> AsyncStream<UpdaterStatus>
    var checkForUpdates: @Sendable () async -> Void
    var dismissFailure: @Sendable () async -> Void
    var preferences: @Sendable () async -> UpdaterPreferences
    var setAutomaticallyChecksForUpdates: @Sendable (Bool) async -> Void
    var setChannel: @Sendable (UpdateChannel) async -> Void
    var preferenceChanges: @Sendable () -> AsyncStream<UpdaterPreferences>

    /// A controller exists only for a build whose resolved status is available,
    /// so the live client is never constructed around a missing updater.
    static func live(controller: SparkleUpdaterController) -> Self {
        Self(
            status: {
                await controller.status()
            },
            statusChanges: {
                controller.statusChanges()
            },
            checkForUpdates: {
                await controller.checkForUpdates()
            },
            dismissFailure: {
                await controller.dismissFailure()
            },
            preferences: {
                await controller.preferences()
            },
            setAutomaticallyChecksForUpdates: { enabled in
                await controller.setAutomaticallyChecksForUpdates(enabled)
            },
            setChannel: { channel in
                await controller.setChannel(channel)
            },
            preferenceChanges: {
                controller.preferenceChanges()
            })
    }

    /// Inert client for a build whose resolved status disables Sparkle
    /// (unavailable or externally managed). Preserves the resolved status so
    /// Settings and the menu can explain exactly why checks are off.
    static func disabled(status: UpdaterStatus) -> Self {
        Self(
            status: { status },
            statusChanges: {
                // Inert client: an immediately-finished stream lets launch-path
                // effects conclude instead of awaiting a broadcast that never comes.
                AsyncStream { $0.finish() }
            },
            checkForUpdates: {},
            dismissFailure: {},
            preferences: { UpdaterPreferences() },
            setAutomaticallyChecksForUpdates: { _ in },
            setChannel: { _ in },
            preferenceChanges: {
                AsyncStream { $0.finish() }
            })
    }

    static let disabled = Self.disabled(
        status: .unavailable(reason: "Software updates are not configured for this build."))
}

extension UpdaterClient: DependencyKey {
    static let liveValue = Self.disabled
    static let testValue = Self.disabled
}

extension DependencyValues {
    var updater: UpdaterClient {
        get { self[UpdaterClient.self] }
        set { self[UpdaterClient.self] = newValue }
    }
}
