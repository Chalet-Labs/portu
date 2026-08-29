import Foundation
import Testing

struct UpdaterSettingsUITests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func `updates settings tab renders update preferences section with automatic check toggle and channel picker`() throws {
        let settings = try string("Sources/Portu/Features/Settings/UpdatesSettingsView.swift")
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

    // MARK: - SettingsUpdateStatusNotice

    @Test func `settings update status notice renders nothing while availability is resolving`() throws {
        let source = try string("Sources/Portu/Features/Settings/SettingsUpdateStatusNotice.swift")
        #expect(
            source.contains("case .available, .resolving:"),
            "Resolving must fall through to no notice so no unavailable banner flashes during launch resolution")
    }

    @Test func `automatic check subtitle reports checking while updater status is resolving`() throws {
        let settings = try string("Sources/Portu/Features/Settings/UpdatesSettingsView.swift")
        let notice = try string("Sources/Portu/Features/Settings/SettingsUpdateStatusNotice.swift")
        #expect(settings.contains("store.updaterStatus.updateSettingsSubtitle"))
        #expect(notice.contains("var updateSettingsSubtitle"))
        #expect(notice.contains("Checking update availability…"))
        #expect(notice.contains("if isResolving"))
    }

    @Test func `updates controls remain disabled until updater availability resolves`() throws {
        let settings = try string("Sources/Portu/Features/Settings/UpdatesSettingsView.swift")
        #expect(
            settings.contains(".disabled(!store.updaterStatus.isUpdaterEligible)"),
            "Controls must stay disabled while resolving because isUpdaterEligible is false for .resolving")
    }

    @Test func `updates settings tab includes SettingsUpdateStatusNotice`() throws {
        let settings = try string("Sources/Portu/Features/Settings/UpdatesSettingsView.swift")
        #expect(
            settings.contains("SettingsUpdateStatusNotice"),
            "The updates settings tab must embed the update status notice view")
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
