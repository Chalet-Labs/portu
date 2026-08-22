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

final class UpdaterPreferencesBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: (continuation: AsyncStream<UpdaterPreferences>.Continuation, primed: Bool)] = [:]
    private var latestPreferences: UpdaterPreferences

    init(initialPreferences: UpdaterPreferences) {
        self.latestPreferences = initialPreferences
    }

    func currentPreferences() -> UpdaterPreferences {
        lock.withLock {
            latestPreferences
        }
    }

    func update(_ preferences: UpdaterPreferences) {
        // Deliver only to subscribers whose initial replay has completed
        // (primed). A fresh subscriber registered mid-flight misses this update,
        // but its own replay yields `latestPreferences` — which already contains
        // it — so nothing is lost and ordering per subscriber is preserved.
        let continuations: [AsyncStream<UpdaterPreferences>.Continuation] = lock.withLock {
            latestPreferences = preferences
            return subscribers.values
                .filter(\.primed)
                .map(\.continuation)
        }
        for continuation in continuations {
            continuation.yield(preferences)
        }
    }

    func stream() -> AsyncStream<UpdaterPreferences> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self, id] _ in
                self?.removeSubscriber(id: id)
            }
            let initial: UpdaterPreferences = lock.withLock {
                subscribers[id] = (continuation, primed: false)
                return latestPreferences
            }
            // Initial replay happens outside the lock (yield can synchronously
            // resume a suspended consumer). update() withholds values from
            // unprimed subscribers, so nothing can precede this replay.
            // Re-read latest and prime in ONE lock section: an update landing
            // after the read but before priming is otherwise withheld forever
            // (unprimed subscribers get no updates), leaving Settings stale.
            let latest = lock.withLock {
                if var entry = subscribers[id] {
                    entry.primed = true
                    subscribers[id] = entry
                }
                return latestPreferences
            }
            if latest != initial {
                continuation.yield(latest)
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

    init(preferencesProvider: (@MainActor () -> UpdaterPreferences)? = nil) {
        self.preferencesProvider = preferencesProvider
        super.init()
    }

    @objc func allowedChannels(for _: SPUUpdater) -> Set<String> {
        let prefs = preferencesProvider?() ?? UpdaterPreferences()
        switch prefs.channel {
        case .stable:
            return []
        case .alpha:
            return ["alpha"]
        }
    }
}

@MainActor
final class SparkleUpdaterController {
    private let controller: SPUStandardUpdaterController
    private let delegate: ChannelUpdaterDelegate
    private let broadcaster: UpdaterPreferencesBroadcaster
    private var kvoObservation: NSKeyValueObservation?
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
        let broadcaster = UpdaterPreferencesBroadcaster(initialPreferences: initialPrefs)
        self.broadcaster = broadcaster

        delegate.preferencesProvider = { [weak broadcaster] in
            broadcaster?.currentPreferences() ?? UpdaterPreferences()
        }

        // Sparkle owns the SUEnableAutomaticChecks default (the native permission
        // prompt and Settings toggles both persist through it); never mirror it.
        controller.updater.automaticallyDownloadsUpdates = false
        controller.startUpdater()
        self.controller = controller

        self.kvoObservation = controller.updater.observe(
            \.automaticallyChecksForUpdates,
            options: [.new]) { [weak self] updater, _ in
                Task { @MainActor [weak self] in
                    self?.handleAutomaticChecksKVOChanged(updater.automaticallyChecksForUpdates)
                }
            }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func preferences() -> UpdaterPreferences {
        broadcaster.currentPreferences()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        // Assign unconditionally so Sparkle records the user's decision even when
        // the effective value is unchanged (declining an already-off prompt).
        controller.updater.automaticallyChecksForUpdates = enabled
        let current = broadcaster.currentPreferences()
        if current.automaticallyChecksForUpdates != enabled {
            let updated = UpdaterPreferences(
                automaticallyChecksForUpdates: enabled,
                channel: current.channel)
            broadcaster.update(updated)
        }
    }

    // Serialization: both setters run on the main actor (as does Sparkle), so
    // writes commit one at a time in the order tasks reach it. The reducer's
    // cancel-in-flight ID supplies ordering — a newer selection cancels the
    // older effect before it can re-enter here.
    func setChannel(_ channel: UpdateChannel) {
        userDefaults.set(channel.rawValue, forKey: Self.channelKey)
        let current = broadcaster.currentPreferences()
        if current.channel != channel {
            let updated = UpdaterPreferences(
                automaticallyChecksForUpdates: current.automaticallyChecksForUpdates,
                channel: channel)
            broadcaster.update(updated)
        }
    }

    nonisolated func preferenceChanges() -> AsyncStream<UpdaterPreferences> {
        broadcaster.stream()
    }

    private func handleAutomaticChecksKVOChanged(_ enabled: Bool) {
        // The native prompt answered directly through Sparkle; just mirror the
        // observed value into the broadcast so TCA state cannot drift.
        let current = broadcaster.currentPreferences()
        if current.automaticallyChecksForUpdates != enabled {
            let updated = UpdaterPreferences(
                automaticallyChecksForUpdates: enabled,
                channel: current.channel)
            broadcaster.update(updated)
        }
    }
}

struct UpdaterClient: Sendable {
    // False for the inert `.disabled` client (no configured feed, e.g. Release
    // builds without updater credentials); Settings gates its update controls on it.
    var isAvailable: @Sendable () -> Bool
    var checkForUpdates: @Sendable () async -> Void
    var preferences: @Sendable () async -> UpdaterPreferences
    var setAutomaticallyChecksForUpdates: @Sendable (Bool) async -> Void
    var setChannel: @Sendable (UpdateChannel) async -> Void
    var preferenceChanges: @Sendable () -> AsyncStream<UpdaterPreferences>

    static func live(controller: SparkleUpdaterController?) -> Self {
        guard let controller else {
            return .disabled
        }
        return Self(
            isAvailable: { true },
            checkForUpdates: {
                await controller.checkForUpdates()
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

    static let disabled = Self(
        isAvailable: { false },
        checkForUpdates: {},
        preferences: { UpdaterPreferences() },
        setAutomaticallyChecksForUpdates: { _ in },
        setChannel: { _ in },
        preferenceChanges: {
            // Inert client: an immediately-finished stream lets launch-path effects
            // conclude instead of awaiting a broadcast that never comes.
            AsyncStream { $0.finish() }
        })
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
