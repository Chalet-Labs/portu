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
        #expect(!project.contains("github.com/Chalet-Labs/portu/releases"))
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

    // MARK: - Owner build settings

    @Test func `debug build settings declare development as update owner`() throws {
        let project = try string("project.yml")
        // Debug config block precedes Release in the YAML; split on the Release key to isolate it
        let debugSection = project.components(separatedBy: "        Release:").first ?? ""
        #expect(debugSection.contains("PORTU_UPDATE_OWNER: development"))
    }

    @Test func `release build settings declare directGitHub as update owner`() throws {
        let project = try string("project.yml")
        let releaseSection = project.components(separatedBy: "        Release:").last ?? ""
        #expect(releaseSection.contains("PORTU_UPDATE_OWNER: directGitHub"))
    }

    // MARK: - PortuUpdateOwner parsing

    @Test func `portuUpdateOwner parses directGitHub development and externallyManaged from raw strings`() {
        #expect(PortuUpdateOwner(rawValue: "directGitHub") == .directGitHub)
        #expect(PortuUpdateOwner(rawValue: "development") == .development)
        #expect(PortuUpdateOwner(rawValue: "externallyManaged:Homebrew") == .externallyManaged("Homebrew"))
        #expect(PortuUpdateOwner(rawValue: "externallyManaged: Homebrew ") == .externallyManaged("Homebrew"))
        #expect(PortuUpdateOwner(rawValue: "") == nil)
        #expect(PortuUpdateOwner(rawValue: "unknown") == nil)
    }

    @Test func `externallyManaged owner with blank label fails closed`() {
        // A blank label cannot name the tool that owns updates; it must never
        // resolve to an externally-managed posture rendering empty prose.
        #expect(PortuUpdateOwner(rawValue: "externallyManaged:") == nil)
        #expect(PortuUpdateOwner(rawValue: "externallyManaged:   ") == nil)
    }

    // MARK: - UpdaterStatus resolution

    @Test func `directGitHub owner with valid feed and key produces available status`() {
        // Synthetic key: valid 32-byte Ed25519 public key used in the Debug build fixture
        let validConfig = UpdaterConfiguration(infoDictionary: [
            "SUFeedURL": "https://raw.githubusercontent.com/Chalet-Labs/portu/updates/appcast.xml",
            "SUPublicEDKey": "bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00="
        ])
        let status = UpdaterStatus.resolve(owner: .directGitHub, configuration: validConfig)
        #expect(status.canCheckForUpdates)
        if case .available = status.availability { } else {
            Issue.record("Expected .available availability, got \(status.availability)")
        }
    }

    @Test func `development owner rejects production feed and accepts explicit test feed`() {
        let testKey = "bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00="
        let productionURL = "https://raw.githubusercontent.com/Chalet-Labs/portu/updates/appcast.xml"
        let testFeedURL = "https://raw.githubusercontent.com/Chalet-Labs/portu/master/Tests/Fixtures/Updater/appcast.xml"

        // The production updates-branch feed must be rejected for development builds
        let productionConfig = UpdaterConfiguration(infoDictionary: [
            "SUFeedURL": productionURL,
            "SUPublicEDKey": testKey
        ])
        let productionStatus = UpdaterStatus.resolve(owner: .development, configuration: productionConfig)
        #expect(!productionStatus.canCheckForUpdates, "Development owner must not poll the production feed")
        if case .unavailable = productionStatus.availability { } else {
            Issue.record("Expected .unavailable for development + production feed, got \(productionStatus.availability)")
        }

        // The isolated test fixture feed is accepted for development builds
        let testConfig = UpdaterConfiguration(infoDictionary: [
            "SUFeedURL": testFeedURL,
            "SUPublicEDKey": testKey
        ])
        let testStatus = UpdaterStatus.resolve(owner: .development, configuration: testConfig)
        #expect(testStatus.canCheckForUpdates, "Development owner must accept the isolated test fixture feed")
    }

    @Test func `development owner rejects production feed aliases regardless of host case or query`() {
        let testKey = "bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00="
        let aliases = [
            "https://github.com/Chalet-Labs/portu/raw/updates/appcast.xml",
            "https://www.github.com/Chalet-Labs/portu/raw/updates/appcast.xml",
            "https://RAW.githubusercontent.com/Chalet-Labs/portu/updates/appcast.xml",
            "https://raw.githubusercontent.com/chalet-labs/PORTU/updates/appcast.xml",
            "https://raw.githubusercontent.com/Chalet-Labs/portu/updates/appcast.xml?nocache=1"
        ]
        for alias in aliases {
            let config = UpdaterConfiguration(infoDictionary: [
                "SUFeedURL": alias,
                "SUPublicEDKey": testKey
            ])
            #expect(config != nil, "Alias must parse as a valid configuration: \(alias)")
            let status = UpdaterStatus.resolve(owner: .development, configuration: config)
            #expect(!status.canCheckForUpdates, "Production feed alias must be rejected: \(alias)")
            if case .unavailable = status.availability { } else {
                Issue.record("Expected .unavailable for alias \(alias), got \(status.availability)")
            }
        }

        // Explicit localhost and unrelated feeds remain allowed for proofs.
        let localhost = UpdaterConfiguration(infoDictionary: [
            "SUFeedURL": "https://localhost:8443/appcast.xml",
            "SUPublicEDKey": testKey
        ])
        #expect(UpdaterStatus.resolve(owner: .development, configuration: localhost).canCheckForUpdates)
    }

    @Test func `externallyManaged owner produces externallyManaged status with preserved label`() {
        let status = UpdaterStatus.resolve(owner: .externallyManaged("Homebrew"), configuration: nil)
        #expect(!status.canCheckForUpdates)
        if case let .externallyManaged(owner) = status.availability {
            #expect(owner == "Homebrew")
        } else {
            Issue.record("Expected .externallyManaged availability, got \(status.availability)")
        }
    }

    @Test func `absent or unrecognized owner string fails closed to unavailable`() {
        // A nil owner (key absent from build settings) must never grant update access
        let status = UpdaterStatus.resolve(owner: nil, configuration: nil)
        #expect(!status.canCheckForUpdates)
        if case .unavailable = status.availability { } else {
            Issue.record("Expected .unavailable for nil owner, got \(status.availability)")
        }
    }

    // MARK: - UpdaterFailure

    @Test func `updater failure recovery URL lives in Swift source not in build settings`() throws {
        // The releases URL must not appear in project.yml (existing assertion preserved here too)
        let project = try string("project.yml")
        #expect(
            !project.contains("github.com/Chalet-Labs/portu/releases"),
            "Recovery URL must never be baked into build settings")

        // The URL is a static Swift constant on UpdaterFailure — must match exactly
        #expect(UpdaterFailure.recoveryURL == URL(string: "https://github.com/Chalet-Labs/portu/releases")!)
    }

    @Test func `updaterFailure cases expose message containing required copy`() {
        for failure in [UpdaterFailure.unavailable, .validationFailed] {
            #expect(
                failure.message.contains("The update was not installed"),
                "All failure cases must surface the installation-failure copy; got: \(failure.message)")
        }
    }

    // MARK: - Menu

    @Test func `application menu gates check button on status not on controller instance`() throws {
        let app = try string("Sources/Portu/App/PortuApp.swift")

        // The disabled predicate inside CommandGroup(after: .appInfo) must come from TCA store state,
        // not a direct reference to the stored Sparkle controller property
        let afterCommandGroup = app.components(separatedBy: "CommandGroup(after: .appInfo)").last ?? ""
        let menuBlock = afterCommandGroup.components(separatedBy: "CommandGroup(").first ?? afterCommandGroup

        #expect(
            !menuBlock.contains("updaterController == nil"),
            "Menu must not reference the stored controller; disabled state belongs in store state")
        #expect(
            menuBlock.contains("canCheckForUpdates") || menuBlock.contains("updaterStatus"),
            "Menu disabled state must derive from the store's updaterStatus")
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
