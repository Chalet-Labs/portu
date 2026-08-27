import Foundation
import Sparkle

/// Who is responsible for delivering updates to this build. Parsed from the
/// PORTU_UPDATE_OWNER build setting (surfaced through Info.plist), deliberately
/// independent of the feed/key configuration: a build must be able to declare
/// "Homebrew owns updates" without carrying any Sparkle credentials at all.
enum PortuUpdateOwner: Equatable, Sendable {
    case directGitHub
    case development
    case externallyManaged(String)

    init?(rawValue: String) {
        switch rawValue {
        case "directGitHub":
            self = .directGitHub
        case "development":
            self = .development
        default:
            let prefix = "externallyManaged:"
            guard rawValue.hasPrefix(prefix) else {
                return nil
            }
            let label = String(rawValue.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else {
                // Fail closed: a blank label cannot name the tool that owns
                // updates, so it must never resolve to a posture.
                return nil
            }
            self = .externallyManaged(label)
        }
    }

    init?(infoDictionary: [String: Any]) {
        guard let rawValue = infoDictionary["PortuUpdateOwner"] as? String else {
            return nil
        }
        self.init(rawValue: rawValue)
    }

    init?(bundle: Bundle = .main) {
        guard let infoDictionary = bundle.infoDictionary else {
            return nil
        }
        self.init(infoDictionary: infoDictionary)
    }
}

/// A user-visible, dismissible failure from a finished update cycle. Carried on
/// `UpdaterStatus` rather than replacing it: a failed check changes neither who
/// owns updates nor whether another check may be attempted.
enum UpdaterFailure: Equatable, Sendable {
    case unavailable
    case validationFailed

    /// Manual-recovery page offered whenever an update was not installed. Lives
    /// in Swift source (not build settings) so configuration changes can never
    /// repoint it.
    static let recoveryURL = URL(string: "https://github.com/Chalet-Labs/portu/releases")!

    var message: String {
        switch self {
        case .unavailable:
            "The update was not installed because the update could not be completed. "
                + "You can download the latest version from the releases page."
        case .validationFailed:
            "The update was not installed because it could not be verified as authentic. "
                + "You can download the latest version from the releases page."
        }
    }

    /// Classifies the outcome Sparkle reports through
    /// `updater(_:didFinishUpdateCycleFor:error:)` — the single terminal
    /// callback for every update cycle.
    ///
    /// Returns nil for success and for benign outcomes that must not surface a
    /// notice: `.noUpdateError`, `.installationCanceledError`, and
    /// `.installationAuthorizeLaterError`. Signature and validation failures
    /// (`.signatureError`, `.validationError`) become `.validationFailed`;
    /// every other genuine failure is `.unavailable`.
    init?(terminalUpdateCycleError error: (any Error)?) {
        guard let error else {
            return nil
        }
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else {
            // Not a Sparkle-classified outcome; still a genuine failure.
            self = .unavailable
            return
        }
        switch SUError(rawValue: OSStatus(nsError.code)) {
        case .noUpdateError, .installationCanceledError, .installationAuthorizeLaterError:
            return nil
        case .signatureError, .validationError:
            self = .validationFailed
        default:
            self = .unavailable
        }
    }
}

/// The resolved update posture of this build: who owns updates, whether the
/// user may check right now, and any dismissible failure from the last cycle.
struct UpdaterStatus: Equatable, Sendable {
    enum Availability: Equatable, Sendable {
        case available
        case unavailable(reason: String)
        case externallyManaged(owner: String)
    }

    var availability: Availability
    /// Live builds drive this from Sparkle's KVO-compliant
    /// `SPUUpdater.canCheckForUpdates`, so it dips during an in-flight session
    /// and recovers afterwards — a failed check stays retryable.
    var canCheckForUpdates: Bool
    var failure: UpdaterFailure?

    /// Structural eligibility: whether this build is configured to run Sparkle
    /// at all. Unlike `canCheckForUpdates` — which dips while a session is in
    /// flight — this never moves during normal operation, so Settings gates its
    /// Updates controls on it while the menu keeps the transient flag.
    var isUpdaterEligible: Bool {
        availability == .available
    }

    static let available = UpdaterStatus(
        availability: .available,
        canCheckForUpdates: true,
        failure: nil)

    static func unavailable(reason: String) -> UpdaterStatus {
        UpdaterStatus(
            availability: .unavailable(reason: reason),
            canCheckForUpdates: false,
            failure: nil)
    }

    static func externallyManaged(owner: String) -> UpdaterStatus {
        UpdaterStatus(
            availability: .externallyManaged(owner: owner),
            canCheckForUpdates: false,
            failure: nil)
    }

    /// The production appcast feed published from the `updates` branch, plus
    /// its user-facing github.com alias. A development build pointed at either
    /// would be offered real releases over rehearsal bits, so `.development`
    /// refuses them by normalized host and path: letter case, query, fragment,
    /// port, and scheme never make production content safe, while localhost or
    /// any other explicit proof feed stays allowed.
    private static let productionFeedLocations: [(host: String, path: String)] = [
        (host: "raw.githubusercontent.com", path: "/chalet-labs/portu/updates/appcast.xml"),
        (host: "github.com", path: "/chalet-labs/portu/raw/updates/appcast.xml")
    ]

    private static func isProductionFeed(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased() else {
            return false
        }
        if host.hasPrefix("www.") {
            host.removeFirst("www.".count)
        }
        let path = url.path(percentEncoded: false).lowercased()
        return productionFeedLocations.contains { $0.host == host && $0.path == path }
    }

    /// Resolves the build's update posture from its declared owner and its
    /// Sparkle feed/key configuration. Fails closed: a missing or unrecognized
    /// owner, or an owner whose requirements are unmet, never grants access.
    static func resolve(
        owner: PortuUpdateOwner?,
        configuration: UpdaterConfiguration?) -> UpdaterStatus {
        switch owner {
        case nil:
            return .unavailable(reason: "This build does not declare an update owner.")
        case let .externallyManaged(label):
            // Sparkle stays disabled; the label is preserved so Settings can
            // name the tool that owns updates.
            return .externallyManaged(owner: label)
        case .directGitHub:
            guard configuration != nil else {
                return .unavailable(reason: "This build has no valid update feed configured.")
            }
            return .available
        case .development:
            guard let configuration else {
                return .unavailable(reason: "This build has no valid update feed configured.")
            }
            guard !isProductionFeed(configuration.feedURL) else {
                return .unavailable(
                    reason: "Development builds must not use the production update feed.")
            }
            return .available
        }
    }
}
