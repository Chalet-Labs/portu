import Foundation
@testable import Portu
import Testing

struct UpdaterIntegrationTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func `sparkle is linked only to the app target`() throws {
        let project = try string("project.yml")

        #expect(project.contains("url: https://github.com/sparkle-project/Sparkle"))
        #expect(project.contains("exactVersion: \"2.9.5\""))

        let appTarget = try #require(project.split(separator: "  PortuTests:").first)
        #expect(appTarget.contains("- package: Sparkle"))
        #expect(appTarget.contains("product: Sparkle"))

        let testTarget = try #require(project.split(separator: "  PortuTests:").last)
        #expect(!testTarget.contains("package: Sparkle"))
    }

    @Test func `debug updater uses an isolated HTTPS proof feed while release uses updates branch feed`() throws {
        let project = try string("project.yml")
        let feedPath = "Tests/Fixtures/Updater/appcast.xml"

        #expect(project.contains(
            "PORTU_UPDATE_FEED_URL: \"https://raw.githubusercontent.com/Chalet-Labs/portu/master/\(feedPath)\""))
        #expect(project.contains("PORTU_UPDATE_PUBLIC_KEY:"))
        #expect(project.contains("PORTU_UPDATE_FEED_URL: \"https://raw.githubusercontent.com/Chalet-Labs/portu/updates/appcast.xml\""))
        #expect(project.contains("PORTU_UPDATE_PUBLIC_KEY: \"\""))
        #expect(!project.contains("github.com/Chalet-Labs/portu/releases/download/appcast.xml"))
        let appcast = try string(feedPath)
        #expect(appcast.contains("xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\""))
        #expect(appcast.contains("<channel>"))
        #expect(!appcast.contains("<item>"))
        #expect(!appcast.contains("<enclosure"))
    }

    @Test func `sparkle configuration preserves permission prompt defaults and disables profiling`() throws {
        let info = try propertyList("Sources/Portu/Resources/Info.plist")

        #expect(info["SUFeedURL"] as? String == "$(PORTU_UPDATE_FEED_URL)")
        #expect(info["SUPublicEDKey"] as? String == "$(PORTU_UPDATE_PUBLIC_KEY)")
        #expect(info["SUEnableAutomaticChecks"] == nil)
        #expect(info["SUPromptUserOnFirstLaunch"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
        #expect(info["SUEnableSystemProfiling"] as? Bool == false)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? String == "$(PORTU_VERIFY_UPDATE_BEFORE_EXTRACTION)")
    }

    @Test func `updater configuration requires HTTPS feed and a public key`() {
        let validInfo: [String: Any] = [
            "SUFeedURL": "https://raw.githubusercontent.com/Chalet-Labs/portu/master/Tests/Fixtures/Updater/appcast.xml",
            "SUPublicEDKey": "bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00="
        ]

        #expect(UpdaterConfiguration(infoDictionary: validInfo) != nil)
        #expect(UpdaterConfiguration(infoDictionary: [
            "SUFeedURL": "http://example.test/appcast.xml",
            "SUPublicEDKey": validInfo["SUPublicEDKey"] as Any
        ]) == nil)
        #expect(UpdaterConfiguration(infoDictionary: [
            "SUFeedURL": "",
            "SUPublicEDKey": ""
        ]) == nil)
    }

    @Test func `application menu routes manual checks through the root feature`() throws {
        let app = try string("Sources/Portu/App/PortuApp.swift")

        #expect(app.contains("CommandGroup(after: .appInfo)"))
        #expect(app.contains("Button(\"Check for Updates…\")"))
        #expect(app.contains("store.send(.checkForUpdatesTapped)"))
    }

    private func string(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)
    }

    private func propertyList(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appending(path: path))
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(object as? [String: Any])
    }
}
