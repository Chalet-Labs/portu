import Foundation
@testable import Portu
import Testing

struct UpdaterSettingsUITests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func `general settings tab renders update preferences section with automatic check toggle and channel picker`() throws {
        let settings = try string("Sources/Portu/Features/Settings/SettingsView.swift")
        let channelPicker = try string(
            "Sources/Portu/Features/Settings/SettingsUpdateChannelPicker.swift")

        #expect(settings.contains("title: \"Updates\""))
        #expect(settings.contains("Check for updates automatically"))
        #expect(settings.contains("store.send(.setAutomaticChecksEnabled"))
        #expect(channelPicker.contains("store.send(.setUpdateChannel"))
    }

    @Test func `settings view does not instantiate a separate updater controller or updater`() throws {
        let settings = try string("Sources/Portu/Features/Settings/SettingsView.swift")

        #expect(!settings.contains("SPUStandardUpdaterController"))
        #expect(!settings.contains("SPUUpdater"))
        #expect(!settings.contains("SparkleUpdaterController"))
    }

    private func string(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)
    }
}
