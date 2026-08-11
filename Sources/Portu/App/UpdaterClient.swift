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

@MainActor
final class SparkleUpdaterController {
    private let controller: SPUStandardUpdaterController

    init(configuration _: UpdaterConfiguration) {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        controller.startUpdater()
        self.controller = controller
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct UpdaterClient {
    var checkForUpdates: @Sendable () async -> Void

    static func live(controller: SparkleUpdaterController?) -> Self {
        guard let controller else {
            return .disabled
        }
        return Self(checkForUpdates: {
            await controller.checkForUpdates()
        })
    }

    static let disabled = Self(checkForUpdates: {})
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
