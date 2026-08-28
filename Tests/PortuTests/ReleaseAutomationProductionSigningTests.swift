import Foundation
import Testing

/// Single source of truth for the production Ed25519 public key in tests.
/// Rotating the key touches this constant, `project.yml`, and the generated
/// project — tests referencing the fixture cannot drift from each other.
enum ProductionUpdateSigningFixture {
    static let publicKey = "cOsrWIKHer18euTD1qZi2KJ0Anxc+tW8UPl6da9Pmx4="
}

/// Issue #84 — production update signing boundary.
/// The production Ed25519 private key never enters the repository, PR workflows,
/// or ordinary builds. Signing happens only inside the protected
/// `production-signing` GitHub Actions environment after human approval, and
/// every publication path fails closed before the feed is touched when the key
/// is missing, malformed, or does not match the public key embedded in release
/// builds.
extension ReleaseAutomationTests {
    private static let productionPublicKey = ProductionUpdateSigningFixture.publicKey
    private static let rfc8032Seed = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
    private static let rfc8032PublicKey = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="

    private func workflowJobBlocks(in workflow: String) -> [String: Substring] {
        var blocks: [String: Substring] = [:]
        var lines = workflow.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        // Only the `jobs:` section contains job headers; starting anywhere
        // earlier would misread `on:`'s nested keys (`push:`,
        // `workflow_dispatch:`) as jobs and weaken the assertions below.
        guard let jobsIndex = lines.firstIndex(of: "jobs:") else {
            return blocks
        }
        lines = Array(lines[(jobsIndex + 1)...])
        lines.append("  __end__:")

        var currentName: String?
        var start = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isJobHeader = line.hasPrefix("  ")
                && !line.hasPrefix("   ")
                && trimmed.hasSuffix(":")
                && !trimmed.contains(" ")
            guard isJobHeader else { continue }

            if let name = currentName {
                blocks[name] = lines[start ..< index].joined(separator: "\n")[...]
            }
            currentName = String(trimmed.dropLast())
            start = index
        }
        return blocks
    }

    @Test func `production release builds embed the maintainer public key`() throws {
        let project = try string("project.yml")

        let releaseMarker = try #require(project.range(of: "        Release:"))
        let debugMarker = try #require(project.range(of: "        Debug:"))

        let releaseBlock = project[releaseMarker.upperBound...]
        #expect(releaseBlock.range(
            of: "PORTU_UPDATE_PUBLIC_KEY: \"\(Self.productionPublicKey)\"") != nil)
        // The empty placeholder that shipped unverified release builds is gone.
        #expect(releaseBlock.range(of: "PORTU_UPDATE_PUBLIC_KEY: \"\"") == nil)

        let debugBlock = project[debugMarker.upperBound...]
        #expect(debugBlock.range(
            of: "PORTU_UPDATE_PUBLIC_KEY: \"bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00=\"") != nil)

        // Production and development must not share an update trust anchor.
        #expect(Self.productionPublicKey != "bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00=")
    }

    @Test func `generated project embeds the production trust anchor in release builds`() throws {
        // `just release` and scripts/build.sh build from the checked-in project
        // without regenerating it, so the anchor must live in the pbxproj too.
        let project = try string("Portu.xcodeproj/project.pbxproj")

        #expect(project.contains("PORTU_UPDATE_PUBLIC_KEY = \"\(Self.productionPublicKey)\";"))
        #expect(!project.contains("PORTU_UPDATE_PUBLIC_KEY = \"\";"))
        // The development fixture key stays isolated to the Debug configuration.
        #expect(project.contains("PORTU_UPDATE_PUBLIC_KEY = \"bwdTmUzcenVsxzIQb737hznwxvpJr7uveKIzVkxVd00=\";"))
    }

    @Test func `signing and feed publication run only inside the protected production environment`() throws {
        let workflow = try string(".github/workflows/release.yml")
        let jobs = workflowJobBlocks(in: workflow)

        for (name, block) in jobs {
            let referencesKey = block.contains("PORTU_SPARKLE_PRIVATE_KEY")
            if name == "release" {
                // The build-and-release job runs without approval and must never
                // see private-key material.
                #expect(!referencesKey)
            } else if referencesKey {
                // Any job that can read the signing secret must declare the
                // protected environment before its steps.
                let environment = try #require(block.range(of: "environment: production-signing"))
                let steps = try #require(block.range(of: "steps:"))
                #expect(environment.lowerBound < steps.lowerBound)
            }
        }

        #expect(jobs.values.contains { $0.contains("environment: production-signing") })
        #expect(jobs.values.contains { $0.contains("secrets.PORTU_SPARKLE_PRIVATE_KEY") })
    }

    @Test func `signing credentials have no legacy fallbacks and stay out of helper workflows`() throws {
        let releaseWorkflow = try string(".github/workflows/release.yml")
        let publishScript = try string("scripts/publish_sparkle_appcast.sh")

        // The protected environment secret is the single key source: no
        // `|| secrets.SPARKLE_PRIVATE_KEY` style fallback may reappear.
        for line in releaseWorkflow.split(separator: "\n")
            where line.contains("PORTU_SPARKLE_PRIVATE_KEY: ") {
            #expect(line.contains("${{ secrets.PORTU_SPARKLE_PRIVATE_KEY }}"))
            #expect(!line.contains("||"))
        }
        #expect(!releaseWorkflow.contains("secrets.SPARKLE_PRIVATE_KEY"))
        #expect(!publishScript.contains("PORTU_SPARKLE_PRIVATE_SEED"))
        #expect(!publishScript.contains("${SPARKLE_PRIVATE_KEY:-}"))

        // Credential-free rehearsal inputs survive for the ad-hoc proof flow.
        #expect(publishScript.contains("--ed-key-file"))
        #expect(publishScript.contains("--ed-key-file -"))

        // Helper agent workflows run against pull requests and must not reach
        // update-signing credentials.
        for helper in ["claude.yml", "claude-code-review.yml"] {
            let workflow = try string(".github/workflows/\(helper)")
            #expect(!workflow.contains("SPARKLE"))
            #expect(!workflow.contains("publish_sparkle_appcast"))
        }
    }

    @Test func `signing gate fails closed for missing malformed or mismatched production keys`() throws {
        // Missing key from the protected environment.
        let missing = try runScript(
            "scripts/verify_production_signing.sh",
            arguments: [],
            environment: ["PORTU_SPARKLE_PRIVATE_KEY": ""])
        #expect(missing.status == 2)
        #expect(missing.error.contains("missing"))

        // Malformed key material.
        let malformed = try runScript(
            "scripts/verify_production_signing.sh",
            arguments: [],
            environment: ["PORTU_SPARKLE_PRIVATE_KEY": "not-a-valid-seed!"])
        #expect(malformed.status == 2)
        #expect(malformed.error.contains("malformed"))

        // Well-formed key that does not pair with the public key embedded in
        // release builds (default expectation comes from project.yml).
        let mismatch = try runScript(
            "scripts/verify_production_signing.sh",
            arguments: [],
            environment: ["PORTU_SPARKLE_PRIVATE_KEY": Self.rfc8032Seed])
        #expect(mismatch.status == 1)
        #expect(mismatch.error.contains("does not match the public key embedded in release builds"))

        // Matching pair passes and reports the derived public key.
        let verified = try runScript(
            "scripts/verify_production_signing.sh",
            arguments: ["--expected-public-key", Self.rfc8032PublicKey],
            environment: ["PORTU_SPARKLE_PRIVATE_KEY": Self.rfc8032Seed])
        #expect(verified.status == 0)
        #expect(verified.output.contains(Self.rfc8032PublicKey))
        #expect(!verified.output.localizedCaseInsensitiveContains("private"))
    }

    @Test func `appcast generation verifies the archive signature against the expected public key`() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-expected-key-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let dmg = temporaryDirectory.appending(path: "Portu-7.0.0.dmg")
        try createTestDmg(at: dmg, version: "7.0.0", build: "7000")
        let appcast = temporaryDirectory.appending(path: "appcast.xml")

        let commonArguments = [
            "--version", "7.0.0",
            "--build-number", "7000",
            "--dmg", dmg.path(percentEncoded: false),
            "--appcast", appcast.path(percentEncoded: false),
            "--download-url-prefix", "https://github.com/Chalet-Labs/portu/releases/download/v7.0.0"
        ]

        // Signature produced with the signing seed must verify against the
        // seed's own public key.
        let matching = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: commonArguments + ["--expected-public-key", Self.rfc8032PublicKey],
            input: Self.rfc8032Seed + "\n")
        #expect(matching.status == 0)

        // The same signature must fail against the production public key
        // embedded in release builds.
        try? FileManager.default.removeItem(at: appcast)
        let mismatched = try runScript(
            "scripts/generate_sparkle_appcast.sh",
            arguments: commonArguments + ["--expected-public-key", Self.productionPublicKey],
            input: Self.rfc8032Seed + "\n")
        #expect(mismatched.status != 0)
        #expect(mismatched.error.contains("expected public key"))
    }

    @Test func `gated publication verifies the key first and signs release notes metadata`() throws {
        let workflow = try string(".github/workflows/release.yml")
        let publishScript = try string("scripts/publish_sparkle_appcast.sh")

        let gateIndex = try #require(workflow.range(of: "verify_production_signing.sh")?.lowerBound)
        let publishIndex = try #require(
            workflow.range(of: "publish_sparkle_appcast.sh")?.lowerBound)
        #expect(gateIndex < publishIndex)

        // The gate runs before the release assets are published to the feed and
        // the feed publication carries signed release-note metadata.
        #expect(workflow.contains("--release-notes"))
        #expect(publishScript.contains("--expected-public-key"))

        // The release job only records the version; feed publication cannot run
        // inside the unapproved build job.
        let config = try jsonObject(".releaserc.json")
        let plugins = try #require(config["plugins"] as? [Any])
        let exec = try #require(pluginConfig("@semantic-release/exec", in: plugins))
        #expect(exec["publishCmd"] as? String == "scripts/record_released_version.sh ${nextRelease.version} dist/Portu-${nextRelease.version}.dmg")
        #expect(fileExists("scripts/record_released_version.sh"))
        #expect(fileExists("scripts/verify_production_signing.sh"))
    }

    @Test func `gated publication binds signing to the release job artifact digest`() throws {
        let workflow = try string(".github/workflows/release.yml")
        let recorder = try string("scripts/record_released_version.sh")

        // The build job records the digest of the DMG it produced; the gated
        // job refuses to sign bytes whose digest does not match, closing the
        // mutable-release-asset substitution window before approval.
        #expect(recorder.contains("dmg_sha256="))
        #expect(workflow.contains("dmg_sha256: ${{ steps.semantic.outputs.dmg_sha256 }}"))
        #expect(workflow.contains("retry_sha256"))
        let digestCheckIndex = try #require(workflow.range(
            of: "does not match the digest recorded by the release job")?.lowerBound)
        let gateIndex = try #require(workflow.range(of: "verify_production_signing.sh")?.lowerBound)
        #expect(digestCheckIndex < gateIndex)

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "portu-record-digest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let dmg = temporaryDirectory.appending(path: "Portu-3.0.0.dmg")
        try Data("digest-me".utf8).write(to: dmg)
        let recorded = try runScript(
            "scripts/record_released_version.sh",
            arguments: ["3.0.0", dmg.path(percentEncoded: false)])
        #expect(recorded.status == 0)
        #expect(recorded.output.contains("Recorded DMG digest"))

        let missing = try runScript(
            "scripts/record_released_version.sh",
            arguments: ["3.0.0", temporaryDirectory.appending(path: "absent.dmg").path(percentEncoded: false)])
        #expect(missing.status == 2)
        #expect(missing.error.contains("not found"))
    }

    @Test func `workflow values reach run scripts through env and are validated first`() throws {
        let workflow = try string(".github/workflows/release.yml")

        // No step output, job output, or dispatch input is expanded inside a
        // run body — hostile workflow_dispatch input must never become shell
        // source in steps that hold the signing key.
        #expect(!workflow.contains("\"${{"))
        #expect(!workflow.contains(":-${{"))
        #expect(workflow.contains("SEMVER_REGEX"))
        #expect(workflow.contains("is not a valid semantic version; refusing to publish"))
        #expect(workflow.contains("VERSION: ${{ steps.version.outputs.version }}"))
        #expect(workflow.contains("EXPECTED_PUBLIC_KEY: ${{ steps.signing.outputs.public_key }}"))
    }

    @Test func `key loss guidance requires manual bootstrap and forbids unsigned recovery`() throws {
        let guidance = try string("docs/agents/production-signing.md")

        #expect(guidance.localizedCaseInsensitiveContains("manual-bootstrap"))
        #expect(guidance.localizedCaseInsensitiveContains("unsigned"))
        #expect(guidance.localizedCaseInsensitiveContains("backup"))
        #expect(guidance.localizedCaseInsensitiveContains("recovery rehearsal"))
        #expect(guidance.contains("production-signing"))
        // The guidance must never instruct shipping the private key through the
        // repository or an issue.
        #expect(!guidance.localizedCaseInsensitiveContains("paste the private key"))
    }
}
