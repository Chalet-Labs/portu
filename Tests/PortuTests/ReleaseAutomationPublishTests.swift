import Foundation
import Testing

extension ReleaseAutomationTests {
    @Test func `semantic release config publishes assets with github plugin before executing appcast publish`() throws {
        let config = try jsonObject(".releaserc.json")

        let plugins = try #require(config["plugins"] as? [Any])
        let pluginNames = plugins.compactMap(Self.pluginName)
        #expect(pluginNames.contains("@semantic-release/github"))
        #expect(pluginNames.contains("@semantic-release/exec"))

        // Verify github plugin appears before exec plugin
        let githubIndex = try #require(pluginNames.firstIndex(of: "@semantic-release/github"))
        let execIndex = try #require(pluginNames.firstIndex(of: "@semantic-release/exec"))
        #expect(githubIndex < execIndex)

        let github = try #require(pluginConfig("@semantic-release/github", in: plugins))
        let assets = try #require(github["assets"] as? [[String: String]])
        #expect(assets.contains {
            $0["path"] == "dist/Portu-*.dmg"
                && $0["name"] == "Portu-${nextRelease.version}.dmg"
        })
        #expect(assets.contains {
            $0["path"] == "dist/Portu-*.dmg.sha256"
                && $0["name"] == "Portu-${nextRelease.version}.dmg.sha256"
        })

        let exec = try #require(pluginConfig("@semantic-release/exec", in: plugins))
        #expect(exec["prepareCmd"] as? String == "scripts/package_release_dmg.sh ${nextRelease.version}")
        let publishCmd = try #require(exec["publishCmd"] as? String)
        #expect(publishCmd.contains("scripts/publish_sparkle_appcast.sh"))
        #expect(publishCmd.contains("--version ${nextRelease.version}"))
        #expect(publishCmd.contains("--dmg dist/Portu-${nextRelease.version}.dmg"))
    }

    @Test func `release workflow shares one global non-cancelling concurrency group across release channels`() throws {
        let workflow = try string(".github/workflows/release.yml")

        #expect(workflow.contains("concurrency:"))
        #expect(workflow.contains("cancel-in-progress: false"))
        // Global concurrency group must not be branch-scoped (${{ github.ref }})
        #expect(!workflow.contains("release-${{ github.ref }}"))
        #expect(workflow.contains("group: release") || workflow.contains("group: release-publication") || workflow.contains("group: release-global"))

        // Must support workflow_dispatch for manual appcast publication retry
        #expect(workflow.contains("workflow_dispatch:"))
        #expect(workflow.contains("retry_version"))
        #expect(workflow.contains("Retry Appcast Publication"))
        #expect(workflow.contains("RETRY_VERSION: ${{ inputs.retry_version }}"))
        #expect(workflow.contains("publish_sparkle_appcast.sh --version \"$RETRY_VERSION\""))
    }

    @Test func `pull request workflows cannot publish feed or receive signing credentials`() throws {
        let ciWorkflow = try string(".github/workflows/ci.yml")
        let prTitleWorkflow = try string(".github/workflows/pr-title.yml")

        for workflow in [ciWorkflow, prTitleWorkflow] {
            #expect(!workflow.contains("publish_sparkle_appcast.sh"))
            #expect(!workflow.contains("PORTU_SPARKLE_PRIVATE_KEY"))
            #expect(!workflow.contains("SPARKLE_PRIVATE_KEY"))
            #expect(!workflow.contains("PORTU_SPARKLE_PRIVATE_SEED"))
            #expect(!workflow.contains("ED_KEY_FILE"))
            #expect(!workflow.contains("origin updates"))
        }
    }

    @Test func `release project configuration serves appcast from dedicated updates branch`() throws {
        let project = try string("project.yml")

        #expect(project.contains("PORTU_UPDATE_FEED_URL: \"https://raw.githubusercontent.com/Chalet-Labs/portu/updates/appcast.xml\""))
    }

    @Test func `appcast publication validates public DMG reachability before publishing`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-publish-reachability-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let testDmg = temporaryDirectory.appending(path: "Portu-99.0.0.dmg")
        try createTestDmg(at: testDmg, version: "99.0.0", build: "9900")

        // Reachability check to non-existent GitHub release URL must fail closed
        let result = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "99.0.0",
                "--build-number", "9900",
                "--dmg", testDmg.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v99.0.0",
                "--no-push"
            ],
            input: privateSeed + "\n")

        #expect(result.status != 0)
        let error = result.error
        #expect(error.contains("unreachable") || error.contains("reachability") || error.contains("404") || error.contains("failed"))
    }

    @Test func `appcast publication commits only to updates branch and preserves history`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-publish-branch-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        // Setup bare git remote repository
        let remoteRepo = temporaryDirectory.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: remoteRepo, withIntermediateDirectories: true)
        let initBare = Process()
        initBare.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initBare.arguments = ["init", "--bare", "-b", "master", remoteRepo.path(percentEncoded: false)]
        try initBare.run()
        initBare.waitUntilExit()

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="

        // 1. First stable release (1.0.0)
        let dmg1 = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: dmg1, version: "1.0.0", build: "1000")

        let res1 = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", dmg1.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: privateSeed + "\n")

        #expect(res1.status == 0)

        // 2. Second alpha release (1.1.0-alpha.1)
        let dmg2 = temporaryDirectory.appending(path: "Portu-1.1.0-alpha.1.dmg")
        try createTestDmg(at: dmg2, version: "1.1.0-alpha.1", build: "1101")

        let res2 = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.1.0-alpha.1",
                "--build-number", "1101",
                "--dmg", dmg2.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.1.0-alpha.1",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: privateSeed + "\n")

        #expect(res2.status == 0)

        // Clone updates branch to verify feed content and history preservation
        let cloneDir = temporaryDirectory.appending(path: "verify-clone", directoryHint: .isDirectory)
        let cloneProc = Process()
        cloneProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        cloneProc.arguments = ["clone", "-b", "updates", remoteRepo.path(percentEncoded: false), cloneDir.path(percentEncoded: false)]
        try cloneProc.run()
        cloneProc.waitUntilExit()
        #expect(cloneProc.terminationStatus == 0)

        let appcastPath = cloneDir.appending(path: "appcast.xml").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: appcastPath))

        let appcast = try String(contentsOfFile: appcastPath, encoding: .utf8)
        #expect(appcast.contains("<sparkle:version>1000</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>"))
        #expect(appcast.contains("<sparkle:version>1101</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.1.0-alpha.1</sparkle:shortVersionString>"))
        #expect(appcast.contains("<sparkle:channel>alpha</sparkle:channel>"))

        // Check git commit log on updates branch: must contain [skip ci]
        let logProc = Process()
        let logPipe = Pipe()
        logProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        logProc.arguments = ["-C", cloneDir.path(percentEncoded: false), "log", "-n", "2", "--oneline"]
        logProc.standardOutput = logPipe
        try logProc.run()
        logProc.waitUntilExit()
        let logOutput = String(data: logPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(logOutput.contains("[skip ci]"))
    }

    @Test func `appcast publication is idempotent and cleanly handles rerun on already published release`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-publish-idempotent-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let remoteRepo = temporaryDirectory.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: remoteRepo, withIntermediateDirectories: true)
        let initBare = Process()
        initBare.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initBare.arguments = ["init", "--bare", "-b", "master", remoteRepo.path(percentEncoded: false)]
        try initBare.run()
        initBare.waitUntilExit()

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let dmg = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: dmg, version: "1.0.0", build: "1000")

        // First publication
        let res1 = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", dmg.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: privateSeed + "\n")
        #expect(res1.status == 0)

        // Rerun same publication (idempotent retry)
        let res2 = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", dmg.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: privateSeed + "\n")
        #expect(res2.status == 0)
    }

    @Test func `appcast publication failure leaves previous feed intact and never deletes release assets`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-publish-fail-isolation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let remoteRepo = temporaryDirectory.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: remoteRepo, withIntermediateDirectories: true)
        let initBare = Process()
        initBare.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initBare.arguments = ["init", "--bare", "-b", "master", remoteRepo.path(percentEncoded: false)]
        try initBare.run()
        initBare.waitUntilExit()

        let validSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let dmg1 = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: dmg1, version: "1.0.0", build: "1000")

        // 1. Initial successful publication
        let res1 = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", dmg1.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: validSeed + "\n")
        #expect(res1.status == 0)

        // 2. Second publication attempt with invalid key
        let dmg2 = temporaryDirectory.appending(path: "Portu-1.1.0.dmg")
        try createTestDmg(at: dmg2, version: "1.1.0", build: "1100")

        let res2 = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.1.0",
                "--build-number", "1100",
                "--dmg", dmg2.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.1.0",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: "invalid-key\n")

        #expect(res2.status != 0)
        // Ensure local DMG asset remains intact
        #expect(FileManager.default.fileExists(atPath: dmg2.path(percentEncoded: false)))

        // Verify previous feed on remote repository is still valid and untouched
        let cloneDir = temporaryDirectory.appending(path: "verify-clone-intact", directoryHint: .isDirectory)
        let cloneProc = Process()
        cloneProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        cloneProc.arguments = ["clone", "-b", "updates", remoteRepo.path(percentEncoded: false), cloneDir.path(percentEncoded: false)]
        try cloneProc.run()
        cloneProc.waitUntilExit()

        let appcast = try String(contentsOfFile: cloneDir.appending(path: "appcast.xml").path(percentEncoded: false), encoding: .utf8)
        #expect(appcast.contains("<sparkle:version>1000</sparkle:version>"))
        #expect(!appcast.contains("<sparkle:version>1100</sparkle:version>"))
    }

    @Test func `non-production rehearsal demonstrates DMG-first and feed-last publication for stable and alpha`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-rehearsal-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let remoteRepo = temporaryDirectory.appending(path: "remote.git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: remoteRepo, withIntermediateDirectories: true)
        let initBare = Process()
        initBare.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        initBare.arguments = ["init", "--bare", "-b", "master", remoteRepo.path(percentEncoded: false)]
        try initBare.run()
        initBare.waitUntilExit()

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="

        // Phase 1: Rehearse Stable Release (1.0.0)
        let stableDmg = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: stableDmg, version: "1.0.0", build: "1000")
        let stableSha = temporaryDirectory.appending(path: "Portu-1.0.0.dmg.sha256")
        try "fake-sha256".write(to: stableSha, atomically: true, encoding: .utf8)

        // Step 1: Release assets (DMG, SHA-256) are produced first
        #expect(FileManager.default.fileExists(atPath: stableDmg.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: stableSha.path(percentEncoded: false)))

        // Step 2: Feed is published last
        let stablePublish = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", stableDmg.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: privateSeed + "\n")
        #expect(stablePublish.status == 0)

        // Phase 2: Rehearse Alpha Release (1.1.0-alpha.1)
        let alphaDmg = temporaryDirectory.appending(path: "Portu-1.1.0-alpha.1.dmg")
        try createTestDmg(at: alphaDmg, version: "1.1.0-alpha.1", build: "1101")
        let alphaSha = temporaryDirectory.appending(path: "Portu-1.1.0-alpha.1.dmg.sha256")
        try "fake-sha256".write(to: alphaSha, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: alphaDmg.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: alphaSha.path(percentEncoded: false)))

        let alphaPublish = try runScript(
            "scripts/publish_sparkle_appcast.sh",
            arguments: [
                "--version", "1.1.0-alpha.1",
                "--build-number", "1101",
                "--dmg", alphaDmg.path(percentEncoded: false),
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.1.0-alpha.1",
                "--repo-url", remoteRepo.path(percentEncoded: false),
                "--updates-branch", "updates",
                "--skip-reachability-check"
            ],
            input: privateSeed + "\n")
        #expect(alphaPublish.status == 0)

        // Verification of rehearsal feed on updates branch
        let cloneDir = temporaryDirectory.appending(path: "verify-rehearsal", directoryHint: .isDirectory)
        let cloneProc = Process()
        cloneProc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        cloneProc.arguments = ["clone", "-b", "updates", remoteRepo.path(percentEncoded: false), cloneDir.path(percentEncoded: false)]
        try cloneProc.run()
        cloneProc.waitUntilExit()

        let appcast = try String(contentsOfFile: cloneDir.appending(path: "appcast.xml").path(percentEncoded: false), encoding: .utf8)
        // Stable entry
        #expect(appcast.contains("<sparkle:version>1000</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>"))
        #expect(appcast.contains("Portu-1.0.0.dmg"))
        // Alpha entry
        #expect(appcast.contains("<sparkle:version>1101</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.1.0-alpha.1</sparkle:shortVersionString>"))
        #expect(appcast.contains("<sparkle:channel>alpha</sparkle:channel>"))
        #expect(appcast.contains("Portu-1.1.0-alpha.1.dmg"))
    }
}
