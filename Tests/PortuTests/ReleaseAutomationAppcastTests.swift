import Foundation
import Testing

extension ReleaseAutomationTests {
    private func createTestDmg(
        at path: URL,
        version: String,
        build: String,
        publicKey: String = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=") throws {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "dmg-stage-\(UUID().uuidString)", directoryHint: .isDirectory)
        let contents = staging.appending(path: "Portu.app/Contents", directoryHint: .isDirectory)
        let macos = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.portu.app",
            "CFBundleName": "Portu",
            "CFBundleExecutable": "Portu",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "LSMinimumSystemVersion": "15.0",
            "SUPublicEDKey": publicKey
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contents.appending(path: "Info.plist"))
        try Data("binary".utf8).write(to: macos.appending(path: "Portu"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-volname", "Portu \(version)",
            "-srcfolder", staging.path(percentEncoded: false),
            "-ov",
            "-format", "UDZO",
            path.path(percentEncoded: false)
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    @Test func `stable appcast generation creates authenticated entry with monotonic build and semantic display version`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-appcast-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let testDmg = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: testDmg, version: "1.0.0", build: "1000")

        let releaseNotes = temporaryDirectory.appending(path: "release-notes.md")
        try "# Portu 1.0.0\n\nInitial release with authenticated updates.".write(
            to: releaseNotes,
            atomically: true,
            encoding: .utf8)

        let appcastPath = temporaryDirectory.appending(path: "appcast.xml").path(percentEncoded: false)

        let result = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--release-notes", releaseNotes.path(percentEncoded: false),
                "--link", "https://github.com/Chalet-Labs/portu"
            ],
            input: privateSeed + "\n")

        #expect(result.status == 0)
        #expect(FileManager.default.fileExists(atPath: appcastPath))

        let appcast = try String(contentsOfFile: appcastPath, encoding: .utf8)
        #expect(appcast.contains("xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\""))
        #expect(appcast.contains("<title>Portu</title>"))
        #expect(appcast.contains("<sparkle:version>1000</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>"))
        #expect(appcast.contains("https://github.com/Chalet-Labs/portu/releases/download/v1.0.0/Portu-1.0.0.dmg"))
        let dmgLength = try FileManager.default.attributesOfItem(atPath: testDmg.path(percentEncoded: false))[.size] as? Int ?? 0
        #expect(appcast.contains("length=\"\(dmgLength)\""))
        #expect(appcast.contains("sparkle:edSignature="))
        #expect(!appcast.contains("<sparkle:channel>"))
        #expect(appcast.contains("Initial release with authenticated updates."))
    }

    @Test func `alpha appcast generation tags item with alpha channel`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-appcast-alpha-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let testDmg = temporaryDirectory.appending(path: "Portu-1.1.0-alpha.1.dmg")
        try createTestDmg(at: testDmg, version: "1.1.0-alpha.1", build: "1101")

        let appcastPath = temporaryDirectory.appending(path: "appcast.xml").path(percentEncoded: false)

        let result = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.1.0-alpha.1",
                "--build-number", "1101",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--channel", "alpha",
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.1.0-alpha.1"
            ],
            input: privateSeed + "\n")

        #expect(result.status == 0)
        let appcast = try String(contentsOfFile: appcastPath, encoding: .utf8)
        #expect(appcast.contains("<sparkle:version>1101</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.1.0-alpha.1</sparkle:shortVersionString>"))
        #expect(appcast.contains("<sparkle:channel>alpha</sparkle:channel>"))
    }

    @Test func `appcast generation preserves prior feed items across releases`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-appcast-history-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let appcastPath = temporaryDirectory.appending(path: "appcast.xml").path(percentEncoded: false)

        // 1. Initial stable 1.0.0
        let dmg1 = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: dmg1, version: "1.0.0", build: "1000")
        let res1 = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", dmg1.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: privateSeed + "\n")
        #expect(res1.status == 0)

        // 2. Alpha release 1.1.0-alpha.1
        let dmg2 = temporaryDirectory.appending(path: "Portu-1.1.0-alpha.1.dmg")
        try createTestDmg(at: dmg2, version: "1.1.0-alpha.1", build: "1101")
        let res2 = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.1.0-alpha.1",
                "--build-number", "1101",
                "--dmg", dmg2.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--channel", "alpha",
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.1.0-alpha.1"
            ],
            input: privateSeed + "\n")
        #expect(res2.status == 0)

        // 3. Stable release 1.1.0
        let dmg3 = temporaryDirectory.appending(path: "Portu-1.1.0.dmg")
        try createTestDmg(at: dmg3, version: "1.1.0", build: "1102")
        let res3 = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.1.0",
                "--build-number", "1102",
                "--dmg", dmg3.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.1.0"
            ],
            input: privateSeed + "\n")
        #expect(res3.status == 0)

        let appcast = try String(contentsOfFile: appcastPath, encoding: .utf8)
        #expect(appcast.contains("<sparkle:version>1000</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>"))
        #expect(appcast.contains("<sparkle:version>1101</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.1.0-alpha.1</sparkle:shortVersionString>"))
        #expect(appcast.contains("<sparkle:channel>alpha</sparkle:channel>"))
        #expect(appcast.contains("<sparkle:version>1102</sparkle:version>"))
        #expect(appcast.contains("<sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>"))
    }

    @Test func `signed feed generation embeds signature block in appcast XML`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-appcast-sign-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let testDmg = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: testDmg, version: "1.0.0", build: "1000")

        let appcastPath = temporaryDirectory.appending(path: "appcast.xml").path(percentEncoded: false)

        let result = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--sign-feed"
            ],
            input: privateSeed + "\n")

        #expect(result.status == 0)
        let appcast = try String(contentsOfFile: appcastPath, encoding: .utf8)
        #expect(appcast.contains("sparkle-signatures:"))
        #expect(appcast.contains("edSignature:"))
    }

    @Test func `appcast generation fails closed for missing files and arguments`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-appcast-errors-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let validKey = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let testDmg = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: testDmg, version: "1.0.0", build: "1000")
        let appcastPath = temporaryDirectory.appending(path: "appcast.xml").path(percentEncoded: false)

        // 1. Missing private key
        let missingKey = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: "")
        #expect(missingKey.status == 2)
        #expect(missingKey.error.contains("private key") || missingKey.error.contains("seed") || missingKey.error.contains("key"))

        // 2. Insecure HTTP download URL prefix
        let insecureUrl = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "http://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: validKey + "\n")
        #expect(insecureUrl.status == 2)
        #expect(insecureUrl.error.contains("HTTPS") || insecureUrl.error.contains("https"))

        // 3. Missing DMG file
        let missingDmg = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", temporaryDirectory.appending(path: "nonexistent.dmg").path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: validKey + "\n")
        #expect(missingDmg.status == 2)
        #expect(missingDmg.error.contains("DMG") || missingDmg.error.contains("exist"))

        // 4. Missing release notes file
        let missingNotes = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0",
                "--release-notes", temporaryDirectory.appending(path: "missing-notes.md").path(percentEncoded: false)
            ],
            input: validKey + "\n")
        #expect(missingNotes.status == 2)
        #expect(missingNotes.error.contains("release notes") || missingNotes.error.contains("exist"))
    }

    @Test func `appcast generation fails closed for invalid or mismatched metadata`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-appcast-meta-errors-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let validKey = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let testDmg = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: testDmg, version: "1.0.0", build: "1000")
        let appcastPath = temporaryDirectory.appending(path: "appcast.xml").path(percentEncoded: false)

        // 1. Invalid semver
        let invalidSemver = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "not-a-version",
                "--build-number", "1000",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: validKey + "\n")
        #expect(invalidSemver.status == 2)
        #expect(invalidSemver.error.contains("semantic version"))

        // 2. Invalid build number
        let invalidBuild = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "0",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: validKey + "\n")
        #expect(invalidBuild.status == 2)
        #expect(invalidBuild.error.contains("build number"))

        // 3. Mismatched build number in DMG vs CLI argument
        let mismatchedBuild = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "9999",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: validKey + "\n")
        #expect(mismatchedBuild.status == 1)
        #expect(mismatchedBuild.error.contains("build number") || mismatchedBuild.error.contains("match"))
    }

    @Test func `appcast generation never leaks private seed to disk or feed`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-appcast-leak-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let validSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let testDmg = temporaryDirectory.appending(path: "Portu-1.0.0.dmg")
        try createTestDmg(at: testDmg, version: "1.0.0", build: "1000")
        let appcastPath = temporaryDirectory.appending(path: "appcast.xml").path(percentEncoded: false)

        let result = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: [
                "--version", "1.0.0",
                "--build-number", "1000",
                "--dmg", testDmg.path(percentEncoded: false),
                "--appcast", appcastPath,
                "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v1.0.0"
            ],
            input: validSeed + "\n")

        #expect(result.status == 0)

        let leaked = try runScript(
            "scripts/assert_secret_absent.py",
            arguments: [temporaryDirectory.path(percentEncoded: false)],
            input: validSeed + "\n")
        #expect(leaked.status == 0)
    }
}
