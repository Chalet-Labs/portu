import Foundation
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

    // MARK: - SettingsUpdateStatusNotice (red: file and view do not exist yet)

    @Test func `settings general tab includes SettingsUpdateStatusNotice`() throws {
        let settings = try string("Sources/Portu/Features/Settings/SettingsView.swift")
        #expect(
            settings.contains("SettingsUpdateStatusNotice"),
            "The general settings tab must embed the update status notice view")
    }

    @Test func `settings update status notice exists as a separate view source file`() throws {
        let source = try string("Sources/Portu/Features/Settings/SettingsUpdateStatusNotice.swift")
        #expect(source.contains("struct SettingsUpdateStatusNotice"))
        #expect(source.contains(": View"))
    }

    @Test func `settings update status notice reads from root updater status`() throws {
        let source = try string("Sources/Portu/Features/Settings/SettingsUpdateStatusNotice.swift")
        #expect(
            source.contains("updaterStatus") || source.contains("UpdaterStatus"),
            "Notice must read from the shared root updater status, not a local copy")
    }

    private func string(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)
    }
}
