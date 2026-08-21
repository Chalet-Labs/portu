import Foundation
import Testing

struct ReleaseAutomationTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func `semantic release config publishes alpha prereleases and stable releases`() throws {
        let config = try jsonObject(".releaserc.json")

        let branches = try #require(config["branches"] as? [Any])
        #expect(branches.count == 2)
        #expect(branches.contains { $0 as? String == "master" })
        let alphaBranch = try #require(branches.compactMap { $0 as? [String: Any] }.first {
            $0["name"] as? String == "alpha"
        })
        #expect(alphaBranch["name"] as? String == "alpha")
        #expect(alphaBranch["prerelease"] as? Bool == true)
        #expect(config["tagFormat"] as? String == "v${version}")

        let plugins = try #require(config["plugins"] as? [Any])
        let pluginNames = plugins.compactMap(Self.pluginName)
        #expect(pluginNames == [
            "@semantic-release/commit-analyzer",
            "@semantic-release/release-notes-generator",
            "@semantic-release/github",
            "@semantic-release/exec"
        ])

        let analyzer = try #require(pluginConfig("@semantic-release/commit-analyzer", in: plugins))
        let releaseRules = try #require(analyzer["releaseRules"] as? [[String: Any]])
        #expect(Self.hasRule(type: "feat", release: "minor", in: releaseRules))
        #expect(Self.hasRule(type: "fix", release: "patch", in: releaseRules))
        #expect(Self.hasRule(type: "perf", release: "patch", in: releaseRules))
        #expect(Self.hasRule(type: "chore", release: false, in: releaseRules))

        let github = try #require(pluginConfig("@semantic-release/github", in: plugins))
        #expect(github["successComment"] as? Bool == false)
        #expect(github["failComment"] as? Bool == false)
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
        #expect(exec["publishCmd"] == nil)
    }

    @Test func `package manifest installs semantic release tooling only for development`() throws {
        let manifest = try jsonObject("package.json")

        #expect(manifest["private"] as? Bool == true)
        let scripts = try #require(manifest["scripts"] as? [String: String])
        #expect(scripts["release"] == "semantic-release")
        #expect(scripts["release:dry-run"] == "semantic-release --dry-run")

        let devDependencies = try #require(manifest["devDependencies"] as? [String: String])
        for dependency in [
            "semantic-release",
            "@semantic-release/commit-analyzer",
            "@semantic-release/release-notes-generator",
            "@semantic-release/github",
            "@semantic-release/exec"
        ] {
            #expect(devDependencies[dependency] != nil)
        }

        #expect(devDependencies["@semantic-release/github"] == "^12.0.9")

        let lockfile = try jsonObject("package-lock.json")
        let packages = try #require(lockfile["packages"] as? [String: Any])
        let githubPackage = try #require(packages["node_modules/@semantic-release/github"] as? [String: Any])
        #expect(githubPackage["version"] as? String == "12.0.9")
    }

    @Test func `release workflow runs tests then semantic release on push`() throws {
        let workflow = try string(".github/workflows/release.yml")

        #expect(workflow.contains("push:"))
        #expect(try workflowPushBranches(in: workflow) == ["alpha", "master"])
        #expect(workflow.contains("contents: write"))
        #expect(workflow.contains("npm ci"))
        #expect(workflow.contains("just generate"))
        #expect(workflow.contains("just build"))
        #expect(workflow.contains("just test-packages"))
        #expect(workflow.contains("just test"))
        #expect(workflow.contains("npx semantic-release"))
        #expect(workflow.contains("SEMANTIC_RELEASE_TOKEN"))
        #expect(workflow.contains("semantic-release-bot"))

        let testPackagesIndex = try #require(workflow.range(of: "just test-packages")?.lowerBound)
        let testAppIndex = try #require(workflow.range(of: "just test\n")?.lowerBound)
        let releaseIndex = try #require(workflow.range(of: "npx semantic-release")?.lowerBound)
        #expect(testPackagesIndex < testAppIndex)
        #expect(testAppIndex < releaseIndex)
    }

    @Test func `pull request title workflow enforces conventional squash titles`() throws {
        let workflow = try string(".github/workflows/pr-title.yml")

        #expect(workflow.contains("pull_request:"))
        #expect(workflow.contains("PR_TITLE: ${{ github.event.pull_request.title }}"))
        #expect(workflow.contains("feat|fix|perf|docs|test|tests|refactor|style|build|ci|chore|revert"))
        #expect(workflow.contains("PR title must use Conventional Commits"))
    }

    @Test func `release packaging uses ad hoc signing without paid Apple credentials`() throws {
        let packageScript = try string("scripts/package_release_dmg.sh")
        let workflow = try string(".github/workflows/release.yml")

        #expect(packageScript.contains("CODE_SIGN_IDENTITY=\"-\""))
        #expect(packageScript.contains("PORTU_CODE_SIGN_IDENTITY") == false)
        #expect(packageScript.contains("PORTU_DEVELOPMENT_TEAM") == false)
        #expect(packageScript.contains("PORTU_PROVISIONING_PROFILE_SPECIFIER") == false)
        #expect(packageScript.contains("CODE_SIGNING_REQUIRED=YES"))
        #expect(packageScript.contains("codesign -d --entitlements") == false)
        #expect(workflow.contains("PORTU_SIGNING_CERTIFICATE_P12_BASE64") == false)
        #expect(workflow.contains("PORTU_SIGNING_CERTIFICATE_PASSWORD") == false)
        #expect(workflow.contains("PORTU_PROVISIONING_PROFILE_BASE64") == false)
        #expect(workflow.contains("Install release signing assets") == false)
        #expect(packageScript.contains("BUNDLE_MARKETING_VERSION=\"${VERSION%%[-+]*}\""))
        #expect(packageScript.contains("MARKETING_VERSION=\"$BUNDLE_MARKETING_VERSION\""))
        #expect(packageScript.contains("CURRENT_PROJECT_VERSION=\"$BUILD_NUMBER\""))
        #expect(packageScript.contains(#"${UPDATE_BUILD_SETTINGS[@]+"${UPDATE_BUILD_SETTINGS[@]}"}"#))
        #expect(packageScript.contains("hdiutil create"))
        #expect(packageScript.contains("verify_dmg"))
        #expect(packageScript.contains("hdiutil verify \"$dmg_path\""))
        #expect(packageScript.contains("for attempt in 1 2 3"))
        #expect(packageScript.contains("shasum -a 256"))
        #expect(packageScript.contains("CFBundleShortVersionString"))
        #expect(packageScript.contains("expected CFBundleShortVersionString $BUNDLE_MARKETING_VERSION"))
        #expect(fileExists("scripts/mark_github_release_prerelease.sh") == false)
    }

    @Test func `proof updater configuration requires HTTPS and a valid disposable public key`() throws {
        let validKey = "bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00="

        let valid = try runScript(
            "scripts/validate_sparkle_proof_configuration.sh",
            arguments: ["https://localhost:8443/appcast.xml", validKey])
        #expect(valid.status == 0)

        let insecure = try runScript(
            "scripts/validate_sparkle_proof_configuration.sh",
            arguments: ["http://localhost:8443/appcast.xml", validKey])
        #expect(insecure.status == 2)
        #expect(insecure.error.contains("HTTPS"))

        let malformedKey = try runScript(
            "scripts/validate_sparkle_proof_configuration.sh",
            arguments: ["https://localhost:8443/appcast.xml", "not-a-public-key"])
        #expect(malformedKey.status == 2)
        #expect(malformedKey.error.contains("32-byte"))
    }

    @Test func `proof release overrides are explicit and verify the archive before extraction`() throws {
        let packageScript = try string("scripts/package_release_dmg.sh")
        let proofScript = try string("scripts/prepare_sparkle_adhoc_proof.sh")
        let secretScanner = try string("scripts/assert_secret_absent.py")
        let infoPlist = try string("Sources/Portu/Resources/Info.plist")
        let project = try string("project.yml")

        #expect(packageScript.contains("PORTU_SPARKLE_PROOF"))
        #expect(packageScript.contains("validate_sparkle_proof_configuration.sh"))
        #expect(packageScript.contains("PORTU_UPDATE_FEED_URL"))
        #expect(packageScript.contains("PORTU_UPDATE_PUBLIC_KEY"))
        #expect(packageScript.contains("PORTU_VERIFY_UPDATE_BEFORE_EXTRACTION=YES"))
        #expect(infoPlist.contains("<key>SUVerifyUpdateBeforeExtraction</key>"))
        #expect(infoPlist.contains("<string>$(PORTU_VERIFY_UPDATE_BEFORE_EXTRACTION)</string>"))
        #expect(project.contains("PORTU_VERIFY_UPDATE_BEFORE_EXTRACTION: NO"))
        #expect(proofScript.contains("signature_metadata=\"$(codesign -d --verbose=4"))
        #expect(proofScript.contains("grep -q '^Signature=adhoc$' <<< \"$signature_metadata\""))
        #expect(!proofScript.contains("grep -R -F -- \"$PRIVATE_SEED\""))
        #expect(proofScript.contains("scripts/assert_secret_absent.py"))
        #expect(secretScanner.contains("artifact.read(CHUNK_SIZE)"))
        #expect(!secretScanner.contains("read_bytes"))
        #expect(proofScript.contains("TAMPERED_LENGTH=\"$(stat -f '%z' \"$TAMPERED_DMG\")\""))
        #expect(proofScript.contains("TAMPERED_APPCAST_LENGTH"))
        #expect(proofScript.contains("\"archive_length\": int(\"$TAMPERED_LENGTH\")"))
        #expect(proofScript.contains("verify_release_dmg() ("))
        #expect(proofScript.contains("trap cleanup_mounted_release EXIT"))
        #expect(proofScript.contains("ARTIFACTS_DIR=\"$ROOT_DIR/.build/DerivedData/SourcePackages/artifacts\""))
        #expect(proofScript.contains("-print -quit 2>/dev/null || true"))
    }

    @Test func `proof key derivation matches the RFC 8032 Ed25519 vector`() throws {
        let privateSeed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
        let expectedPublicKey = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="

        let result = try runScript(
            "scripts/derive_sparkle_public_key.swift",
            arguments: [],
            input: privateSeed + "\n")

        #expect(result.status == 0)
        #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == expectedPublicKey)
        #expect(!result.error.localizedCaseInsensitiveContains("error:"))
    }

    @Test func `proof secret scanner detects a seed in a large binary artifact`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-secret-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let secret = "issue-79-disposable-private-seed"
        var artifact = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        artifact.append(Data(secret.utf8))
        artifact.append(Data(repeating: 0x42, count: 2 * 1024 * 1024))
        try artifact.write(to: temporaryDirectory.appending(path: "proof.dmg"))

        let leaked = try runScript(
            "scripts/assert_secret_absent.py",
            arguments: [temporaryDirectory.path(percentEncoded: false)],
            input: secret + "\n")
        #expect(leaked.status == 1)
        #expect(leaked.error.contains("secret found"))

        try Data(repeating: 0x43, count: 4 * 1024 * 1024)
            .write(to: temporaryDirectory.appending(path: "proof.dmg"), options: .atomic)
        let absent = try runScript(
            "scripts/assert_secret_absent.py",
            arguments: [temporaryDirectory.path(percentEncoded: false)],
            input: secret + "\n")
        #expect(absent.status == 0)
    }

    @Test func `proof preparation plan requires HTTPS and increasing build numbers`() throws {
        let tailscale = try runScript(
            "scripts/prepare_sparkle_adhoc_proof.sh",
            arguments: [
                "--base-url", "https://works-macbook-pro-1.tailb38892.ts.net:8444",
                "--origin-port", "8443",
                "--n-version", "79.0.0",
                "--n-build", "79000",
                "--next-version", "79.0.1",
                "--next-build", "79001",
                "--output", ".build/updater-proof",
                "--plan-only"
            ])
        #expect(tailscale.status == 0)
        #expect(tailscale.output.contains(
            "proof_feed_url=https://works-macbook-pro-1.tailb38892.ts.net:8444/appcast.xml"))
        #expect(tailscale.output.contains(
            "install_url=https://works-macbook-pro-1.tailb38892.ts.net:8444/install.dmg"))
        #expect(tailscale.output.contains("origin_url=https://localhost:8443"))
        #expect(tailscale.output.contains(
            "tailscale_serve_command=tailscale serve --bg --https=8444 --set-path=/ https+insecure://localhost:8443"))

        let valid = try runScript(
            "scripts/prepare_sparkle_adhoc_proof.sh",
            arguments: [
                "--base-url", "https://localhost:8443",
                "--n-version", "79.0.0",
                "--n-build", "79000",
                "--next-version", "79.0.1",
                "--next-build", "79001",
                "--output", ".build/updater-proof",
                "--plan-only"
            ])
        #expect(valid.status == 0)
        #expect(valid.output.contains("proof_feed_url=https://localhost:8443/appcast.xml"))
        #expect(valid.output.contains("n=79.0.0+79000"))
        #expect(valid.output.contains("next=79.0.1+79001"))
        #expect(!valid.output.localizedCaseInsensitiveContains("private"))

        let insecure = try runScript(
            "scripts/prepare_sparkle_adhoc_proof.sh",
            arguments: [
                "--base-url", "http://localhost:8443",
                "--n-version", "79.0.0",
                "--n-build", "79000",
                "--next-version", "79.0.1",
                "--next-build", "79001",
                "--output", ".build/updater-proof",
                "--plan-only"
            ])
        #expect(insecure.status == 2)
        #expect(insecure.error.contains("HTTPS"))

        let publicInternetHost = try runScript(
            "scripts/prepare_sparkle_adhoc_proof.sh",
            arguments: [
                "--base-url", "https://example.com",
                "--n-version", "79.0.0",
                "--n-build", "79000",
                "--next-version", "79.0.1",
                "--next-build", "79001",
                "--output", ".build/updater-proof",
                "--plan-only"
            ])
        #expect(publicInternetHost.status == 2)
        #expect(publicInternetHost.error.contains("Tailscale HTTPS hostname"))

        let nonIncreasing = try runScript(
            "scripts/prepare_sparkle_adhoc_proof.sh",
            arguments: [
                "--base-url", "https://localhost:8443",
                "--n-version", "79.0.0",
                "--n-build", "79000",
                "--next-version", "79.0.1",
                "--next-build", "79000",
                "--output", ".build/updater-proof",
                "--plan-only"
            ])
        #expect(nonIncreasing.status == 2)
        #expect(nonIncreasing.error.contains("greater"))
    }
}

extension ReleaseAutomationTests {
    func string(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)
    }

    private func jsonObject(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appending(path: path))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot.appending(path: path).path(percentEncoded: false))
    }

    func runScript(
        _ path: String,
        arguments: [String],
        input: String? = nil) throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        let captureDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-script-capture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: captureDirectory) }
        let outputURL = captureDirectory.appending(path: "stdout")
        let errorURL = captureDirectory.appending(path: "stderr")
        try Data().write(to: outputURL)
        try Data().write(to: errorURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        let inputPipe = Pipe()
        process.executableURL = repoRoot.appending(path: path)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        if input != nil {
            process.standardInput = inputPipe
        }

        try process.run()
        if let input {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try inputPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()

        let output = try String(bytes: Data(contentsOf: outputURL), encoding: .utf8) ?? ""
        let error = try String(bytes: Data(contentsOf: errorURL), encoding: .utf8) ?? ""
        return (process.terminationStatus, output, error)
    }

    private func workflowPushBranches(in workflow: String) throws -> Set<String> {
        let lines = workflow.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let pushIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "push:" }) else {
            return []
        }
        let pushIndent = leadingSpaceCount(lines[pushIndex])

        for index in lines.indices.dropFirst(pushIndex + 1) {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let indent = leadingSpaceCount(line)
            if indent <= pushIndent {
                break
            }

            guard trimmed.hasPrefix("branches:") else { continue }

            let branchIndent = indent
            let value = trimmed.dropFirst("branches:".count).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") {
                return Set(value
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            }

            var branches = Set<String>()
            for branchLine in lines.indices.dropFirst(index + 1).map({ lines[$0] }) {
                let branchTrimmed = branchLine.trimmingCharacters(in: .whitespaces)
                guard !branchTrimmed.isEmpty else { continue }

                let indent = leadingSpaceCount(branchLine)
                if indent <= branchIndent {
                    break
                }

                if branchTrimmed.hasPrefix("-") {
                    branches.insert(
                        branchTrimmed
                            .dropFirst()
                            .trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            return branches
        }

        return []
    }

    private func leadingSpaceCount(_ line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    private static func pluginName(_ plugin: Any) -> String? {
        if let name = plugin as? String {
            return name
        }
        if let pair = plugin as? [Any] {
            return pair.first as? String
        }
        return nil
    }

    private static func hasRule(type: String, release: AnyHashable, in rules: [[String: Any]]) -> Bool {
        rules.contains { rule in
            guard rule["type"] as? String == type else {
                return false
            }
            if let stringRelease = rule["release"] as? String {
                return release == AnyHashable(stringRelease)
            }
            if let boolRelease = rule["release"] as? Bool {
                return release == AnyHashable(boolRelease)
            }
            return false
        }
    }

    private func pluginConfig(_ name: String, in plugins: [Any]) -> [String: Any]? {
        for plugin in plugins {
            guard
                let pair = plugin as? [Any],
                pair.first as? String == name
            else { continue }
            return pair.dropFirst().first as? [String: Any]
        }
        return nil
    }
}
