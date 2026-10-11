import Foundation
import Testing

/// Debug builds sign with the developer's Apple Development identity when `Configs/Local.xcconfig`
/// exists. Ad hoc and self-signed builds get a `cdhash:` keychain partition that changes with every
/// rebuild, so the keychain asked for access again after each build.
///
/// Every test runs a copy of the setup script inside a temporary checkout, so a regression can never
/// overwrite the developer's real `Configs/Local.xcconfig`.
extension ReleaseAutomationTests {
    @Test func `local signing setup writes a manual Apple Development config for the identity team`() throws {
        let stub = try SigningSetupStub(this: self, identities: [
            ("Portu Local Development", "subject= /CN=Portu Local Development/OU=OTHERTEAM1/O=Portu Local Development"),
            (
                "Apple Development: Test Person (MEMBER0001)",
                "subject= /UID=USER000001/CN=Apple Development: Test Person (MEMBER0001)/OU=TESTTEAM01/O=Test Person/C=US")
        ])
        defer { stub.remove() }

        let result = try stub.run([])

        #expect(result.status == 0)
        let config = try String(contentsOfFile: stub.defaultOutputPath, encoding: .utf8)
        #expect(config.contains("CODE_SIGN_STYLE = Manual"))
        #expect(config.contains("CODE_SIGN_IDENTITY = Apple Development\n"))
        #expect(config.contains("DEVELOPMENT_TEAM = TESTTEAM01"))
        #expect(config.contains("PROVISIONING_PROFILE_SPECIFIER =\n"))
        #expect(!config.contains("OTHERTEAM1"))
        #expect(!config.contains("MEMBER0001"))
    }

    @Test func `local signing setup writes to the requested output path`() throws {
        let stub = try SigningSetupStub(this: self, identities: [
            (
                "Apple Development: Test Person (MEMBER0001)",
                "subject=CN = Apple Development: Test Person (MEMBER0001), OU = TESTTEAM01, O = Test Person, C = US")
        ])
        defer { stub.remove() }
        let output = stub.directory.appending(path: "custom dir/Local.xcconfig").path(percentEncoded: false)

        let result = try stub.run(["--output", output])

        #expect(result.status == 0)
        let config = try String(contentsOfFile: output, encoding: .utf8)
        #expect(config.contains("DEVELOPMENT_TEAM = TESTTEAM01"))
        #expect(!FileManager.default.fileExists(atPath: stub.defaultOutputPath))
    }

    @Test func `local signing setup explains how to get an identity when none exists`() throws {
        let stub = try SigningSetupStub(this: self, identities: [
            ("Portu Local Development", "subject= /CN=Portu Local Development/OU=OTHERTEAM1/O=Portu Local Development")
        ])
        defer { stub.remove() }

        let result = try stub.run([])

        #expect(result.status == 1)
        #expect(result.error.contains("Xcode"))
        #expect(result.error.contains("Apple Development"))
        #expect(!FileManager.default.fileExists(atPath: stub.defaultOutputPath))
    }

    @Test func `local signing setup asks for a team when identities span teams`() throws {
        let stub = try SigningSetupStub(this: self, identities: [
            (
                "Apple Development: Test Person (MEMBER0001)",
                "subject= /CN=Apple Development: Test Person (MEMBER0001)/OU=TESTTEAM01/O=Test Person/C=US"),
            (
                "Apple Development: Test Person (MEMBER0002)",
                "subject=CN = Apple Development: Test Person (MEMBER0002), OU = TESTTEAM02, O = Other Org, C = US")
        ])
        defer { stub.remove() }

        let ambiguous = try stub.run([])
        #expect(ambiguous.status == 2)
        #expect(ambiguous.error.contains("  TESTTEAM01\n  TESTTEAM02\n"))
        #expect(!FileManager.default.fileExists(atPath: stub.defaultOutputPath))

        let unknown = try stub.run(["--team", "NOSUCHTEAM"])
        #expect(unknown.status == 2)
        #expect(unknown.error.contains("Available: TESTTEAM01 TESTTEAM02\n"))
        #expect(!FileManager.default.fileExists(atPath: stub.defaultOutputPath))

        let chosen = try stub.run(["--team", "TESTTEAM02"])
        #expect(chosen.status == 0)
        let config = try String(contentsOfFile: stub.defaultOutputPath, encoding: .utf8)
        #expect(config.contains("DEVELOPMENT_TEAM = TESTTEAM02"))
    }

    @Test func `local signing setup accepts a renewed certificate in the same team`() throws {
        let stub = try SigningSetupStub(this: self, identities: [
            (
                "Apple Development: Test Person (MEMBER0001)",
                "subject= /CN=Apple Development: Test Person (MEMBER0001)/OU=TESTTEAM01/O=Test Person/C=US"),
            (
                "Apple Development: Test Person (MEMBER0009)",
                "subject= /CN=Apple Development: Test Person (MEMBER0009)/OU=TESTTEAM01/O=Test Person/C=US")
        ])
        defer { stub.remove() }

        let result = try stub.run([])

        #expect(result.status == 0)
        let config = try String(contentsOfFile: stub.defaultOutputPath, encoding: .utf8)
        #expect(config.contains("DEVELOPMENT_TEAM = TESTTEAM01"))
    }

    @Test(arguments: [["--team", ".*"], ["--team", "testteam01"], ["--team"], ["--output"], ["--bogus"]])
    func `local signing setup rejects malformed arguments`(arguments: [String]) throws {
        let stub = try SigningSetupStub(this: self, identities: [
            (
                "Apple Development: Test Person (MEMBER0001)",
                "subject= /CN=Apple Development: Test Person (MEMBER0001)/OU=TESTTEAM01/O=Test Person/C=US")
        ])
        defer { stub.remove() }

        let result = try stub.run(arguments)

        #expect(result.status == 64)
        #expect(result.error.contains("usage:"))
        #expect(!FileManager.default.fileExists(atPath: stub.defaultOutputPath))
    }

    @Test func `debug builds take signing from an optional untracked local config`() throws {
        let project = try string("project.yml")
        let debugConfig = try string("Configs/Debug.xcconfig")
        let gitignore = try string(".gitignore")

        #expect(project.contains("configFiles:\n  Debug: Configs/Debug.xcconfig"))
        #expect(debugConfig.contains("CODE_SIGN_STYLE = Automatic"))
        #expect(debugConfig.contains(#"#include? "Local.xcconfig""#))
        #expect(gitignore.contains("/Configs/Local.xcconfig"))
        // The project xcconfig has the lowest precedence, so any of these keys in project.yml would
        // override Local.xcconfig. The only one left is the Release target's CODE_SIGN_STYLE.
        #expect(project.components(separatedBy: "CODE_SIGN_STYLE").count == 2)
        #expect(project.contains("Release:\n          CODE_SIGN_STYLE: Automatic"))
        for key in ["CODE_SIGN_IDENTITY", "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE"] {
            #expect(!project.contains(key), "project.yml must not set \(key)")
        }
    }

    @Test func `local run script signs through the local config instead of a self-signed identity`() throws {
        let runScript = try string("script/build_and_run.sh")

        #expect(!fileExists("script/ensure_local_signing_identity.sh"))
        #expect(!runScript.contains("ensure_local_signing_identity"))
        #expect(!runScript.contains("CODE_SIGN_IDENTITY"))
        #expect(!runScript.contains("add-trusted-cert"))
    }
}

/// A temporary checkout holding a copy of the setup script, with a fake `security` and `openssl`
/// first on `PATH`. `find-identity` lists the given identities; `find-certificate -c NAME -p`
/// followed by `openssl x509 -noout -subject` prints that identity's certificate subject.
private struct SigningSetupStub {
    let tests: ReleaseAutomationTests
    let directory: URL
    let script: URL
    let defaultOutputPath: String
    private let environment: [String: String]

    init(this tests: ReleaseAutomationTests, identities: [(name: String, subject: String)]) throws {
        self.tests = tests
        self.directory = FileManager.default.temporaryDirectory
            .appending(path: "portu-signing-stub-\(UUID().uuidString)", directoryHint: .isDirectory)
        let checkout = directory.appending(path: "checkout", directoryHint: .isDirectory)
        let bin = directory.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: checkout.appending(path: "script"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        self.script = checkout.appending(path: "script/setup_local_signing.sh")
        try FileManager.default.copyItem(at: tests.repoURL("script/setup_local_signing.sh"), to: script)
        self.defaultOutputPath = checkout.appending(path: "Configs/Local.xcconfig").path(percentEncoded: false)

        let listing = identities.enumerated().map { index, identity in
            let hash = String(repeating: String(index + 1), count: 40)
            return "  \(index + 1)) \(hash) \"\(identity.name)\""
        } + ["     \(identities.count) valid identities found"]
        let data = directory.path(percentEncoded: false)
        try listing.joined(separator: "\n").write(
            to: directory.appending(path: "identities.txt"), atomically: true, encoding: .utf8)
        for (index, identity) in identities.enumerated() {
            try identity.name.write(to: directory.appending(path: "name-\(index)"), atomically: true, encoding: .utf8)
            try identity.subject.write(
                to: directory.appending(path: "subject-\(index)"), atomically: true, encoding: .utf8)
        }

        try Self.writeExecutable(
            """
            #!/bin/bash
            case "$1" in
              find-identity)
                [ "$2 $3 $4" = "-v -p codesigning" ] || exit 66
                cat "\(data)/identities.txt" ;;
              find-certificate)
                while [ $# -gt 0 ]; do
                  if [ "$1" = "-c" ]; then name="$2"; fi
                  shift
                done
                for file in "\(data)"/name-*; do
                  if [ "$(cat "$file")" = "$name" ]; then
                    printf 'STUB-PEM %s\\n' "${file##*-}"
                    exit 0
                  fi
                done
                exit 44 ;;
              *) exit 64 ;;
            esac
            """,
            to: bin.appending(path: "security"))
        try Self.writeExecutable(
            """
            #!/bin/bash
            read -r marker index
            [ "$marker" = "STUB-PEM" ] || exit 65
            cat "\(data)/subject-$index"
            echo
            """,
            to: bin.appending(path: "openssl"))

        self.environment = ["PATH": "\(bin.path(percentEncoded: false)):/usr/bin:/bin"]
    }

    func run(_ arguments: [String]) throws -> (status: Int32, output: String, error: String) {
        try tests.runScript(at: script, arguments: arguments, environment: environment)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
    }
}
