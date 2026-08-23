import Foundation

enum UpdateChannel: String, CaseIterable, Equatable, Sendable {
    case stable
    case alpha
}

struct UpdaterPreferences: Equatable, Sendable {
    var automaticallyChecksForUpdates: Bool
    var channel: UpdateChannel

    init(
        automaticallyChecksForUpdates: Bool = false,
        channel: UpdateChannel = .stable) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.channel = channel
    }
}
