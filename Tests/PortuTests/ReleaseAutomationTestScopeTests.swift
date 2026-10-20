import Foundation
import Testing

struct TestScopeCase: Sendable, CustomTestStringConvertible {
    let paths: [String]
    let groups: [String]

    var testDescription: String {
        paths.isEmpty ? "no paths" : paths.joined(separator: " + ")
    }

    static let rules: [TestScopeCase] = [
        TestScopeCase(
            paths: ["Packages/PortuCore/Sources/PortuCore/DTOs/CurrencyConversionRate.swift"],
            groups: ["app", "core", "network", "ui"]),
        TestScopeCase(
            paths: ["Packages/PortuNetwork/Sources/PortuNetwork/PriceService/PriceService.swift"],
            groups: ["app", "network"]),
        TestScopeCase(paths: ["Packages/PortuUI/Sources/PortuUI/Theme/PortuTheme.swift"], groups: ["app", "ui"]),
        TestScopeCase(paths: ["Sources/Portu/Features/Overview/OverviewFeature.swift"], groups: ["app"]),
        TestScopeCase(paths: ["Tests/PortuTests/OverviewFeatureTests.swift"], groups: ["app"]),
        TestScopeCase(paths: ["Sources/Portu/Resources/Info.plist"], groups: ["app", "release"]),
        TestScopeCase(paths: ["scripts/publish_sparkle_appcast.sh"], groups: ["release"]),
        TestScopeCase(paths: [".github/workflows/ci.yml"], groups: ["release"]),
        TestScopeCase(paths: ["project.yml"], groups: ["app", "core", "network", "release", "ui"]),
        TestScopeCase(paths: ["docs/agents/domain.md"], groups: ["none"]),
        TestScopeCase(paths: ["docs/agents/production-signing.md"], groups: ["release"]),
        TestScopeCase(paths: ["Unknown/file.txt"], groups: ["app", "core", "network", "release", "ui"]),
        TestScopeCase(paths: ["docs/x.md", "Sources/Portu/A.swift"], groups: ["app"]),
        TestScopeCase(paths: [], groups: ["none"])
    ]
}

extension ReleaseAutomationTests {
    @Test(arguments: TestScopeCase.rules)
    func `scope selects the groups a changed path can affect`(_ scope: TestScopeCase) throws {
        #expect(try selectedGroups(scope.paths) == scope.groups)
    }

    @Test func `scope without the fallback selects nothing for a path no rule matches`() throws {
        #expect(try selectedGroups(["Unknown/file.txt"], options: ["--no-fallback"]) == ["none"])
        #expect(try selectedGroups(["Unknown/file.txt", "scripts/x.sh"], options: ["--no-fallback"]) == ["release"])
    }

    /// Release tests are skipped on PRs whose paths don't select `release`, so every repo file a release
    /// test reads, and every file of the suite itself, must match a `release` or `all` rule; the fallback
    /// for unmatched paths doesn't count. Only literals in the test files are seen, not files the scripts read.
    @Test func `every path a release test reads matches a release rule`() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let releaseSuite = #/(?:struct|extension)\s+ReleaseAutomationTests\b/#
        let pathArgument = #/\b(?:string|jsonObject|fileExists|runScript|repoURL)\(\s*"((?:[^"\\]|\\.)*)"/#

        var paths = Set<String>()
        for file in try FileManager.default.subpathsOfDirectory(atPath: testsDirectory.path(percentEncoded: false))
            where file.hasSuffix(".swift") {
            let source = try String(contentsOf: testsDirectory.appending(path: file), encoding: .utf8)
            guard source.contains(releaseSuite) else { continue }
            paths.insert("Tests/PortuTests/" + file)
            let literals = source.matches(of: pathArgument).map { match in
                let literal = String(match.output.1)
                return literal.components(separatedBy: "\\(").first ?? literal
            }
            #expect(!literals.isEmpty, "found no repo path literal in \(file)")
            paths.formUnion(literals)
        }

        #expect(paths.contains(".github/workflows/"))
        for path in paths.sorted() {
            #expect(
                try selectedGroups([path], options: ["--no-fallback"]).contains("release"),
                "no release or all rule matches \(path)")
        }
    }

    @Test func `scope from a base ref covers committed, staged, unstaged, untracked and moved files`() throws {
        let (checkout, script) = try scopeCheckout(rules: """
        [
          { "glob": "committed/*", "groups": ["core"] },
          { "glob": "staged/*", "groups": ["network"] },
          { "glob": "unstaged/*", "groups": ["ui"] },
          { "glob": "untracked/*", "groups": ["app"] },
          { "glob": "moved-from/*", "groups": ["release"] },
          { "glob": "*", "groups": ["none"] }
        ]
        """)
        defer { try? FileManager.default.removeItem(at: checkout) }
        try write("unstaged before\n", to: checkout.appending(path: "unstaged/file.txt"))
        try write("moved file\n", to: checkout.appending(path: "moved-from/file.txt"))
        try commitAll("base", in: checkout)
        try git(["branch", "base"], in: checkout)

        try write("committed\n", to: checkout.appending(path: "committed/file.txt"))
        try git(["mv", "moved-from", "moved-to"], in: checkout)
        try commitAll("change", in: checkout)
        try write("staged\n", to: checkout.appending(path: "staged/file.txt"))
        try git(["add", "staged/file.txt"], in: checkout)
        try write("unstaged after\n", to: checkout.appending(path: "unstaged/file.txt"))
        try write("untracked\n", to: checkout.appending(path: "untracked/file.txt"))

        let result = try runScript(at: script, arguments: ["--base", "base"], environment: Self.isolatedGitConfig)

        #expect(result.status == 0, "\(result.error)")
        #expect(result.output.split(separator: "\n") == ["app", "core", "network", "release", "ui"])
    }

    /// A staged move counts its old path too, and commits made on the base after the fork don't count.
    @Test func `scope from a base ref counts a staged move and skips changes made only on the base`() throws {
        let (checkout, script) = try scopeCheckout(rules: """
        [
          { "glob": "moved-from/*", "groups": ["release"] },
          { "glob": "base-only/*", "groups": ["core"] },
          { "glob": "*", "groups": ["none"] }
        ]
        """)
        defer { try? FileManager.default.removeItem(at: checkout) }
        try write("moved file\n", to: checkout.appending(path: "moved-from/file.txt"))
        try commitAll("fork point", in: checkout)
        try git(["switch", "-q", "-c", "base"], in: checkout)
        try write("base only\n", to: checkout.appending(path: "base-only/file.txt"))
        try commitAll("base moves on", in: checkout)
        try git(["switch", "-q", "master"], in: checkout)
        try git(["mv", "moved-from", "moved-to"], in: checkout)

        let result = try runScript(at: script, arguments: ["--base", "base"], environment: Self.isolatedGitConfig)

        #expect(result.status == 0, "\(result.error)")
        #expect(result.output == "release\n")
    }

    @Test func `scope fails for a base it can't diff`() throws {
        let unknown = try runScript("script/test_scope.sh", arguments: ["--base", "refs/heads/no-such-test-scope-base"])
        #expect(unknown.status != 0)
        #expect(unknown.error.contains("no-such-test-scope-base"))

        let option = try runScript("script/test_scope.sh", arguments: ["--base", "-Sanything"])
        #expect(option.status == 2)
    }

    /// A misspelled group would otherwise select a group no recipe runs, and so no tests at all.
    @Test(arguments: [
        #"[{ "glob": "Sources/*", "groups": ["ap"] }]"#,
        #"[{ "glob": "Sources/*", "groups": [] }]"#,
        #"[{ "groups": ["app"] }]"#
    ])
    func `scope rejects a rules file with an invalid entry`(_ rules: String) throws {
        let (checkout, script) = try scopeCheckout(rules: rules)
        defer { try? FileManager.default.removeItem(at: checkout) }

        let result = try runScript(at: script, arguments: ["--paths-from", "-"], input: "Sources/Portu/A.swift")

        #expect(result.status != 0)
        #expect(result.output.isEmpty)
        #expect(result.error.contains("invalid entry"), "\(result.error)")
    }

    /// Agents often run in sandboxes that can't write temp files; the selector must still select, not print `none`.
    @Test(.enabled(if: Sandbox.canApplyProfile, "sandbox-exec can't apply a profile inside another sandbox"))
    func `scope selects groups where no temp file can be written`() throws {
        let result = try runScript(
            at: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: [
                "-p", Sandbox.noFileWrites,
                repoURL("script/test_scope.sh").path(percentEncoded: false), "--paths-from", "-"
            ],
            input: "Sources/Portu/Features/Overview/OverviewFeature.swift\n")

        #expect(result.status == 0, "\(result.error)")
        #expect(result.output == "app\n")
    }

    private func selectedGroups(_ paths: [String], options: [String] = []) throws -> [String] {
        let result = try runScript(
            "script/test_scope.sh",
            arguments: options + ["--paths-from", "-"],
            input: paths.joined(separator: "\n"))
        #expect(result.status == 0, "\(result.error)")
        return result.output.split(separator: "\n").map(String.init)
    }

    /// A temp checkout holding a copy of the selector and the given rules, so the script finds its rules
    /// and its repo root there.
    private func scopeCheckout(rules: String) throws -> (checkout: URL, script: URL) {
        let checkout = FileManager.default.temporaryDirectory
            .appending(path: "portu-test-scope-\(UUID().uuidString)", directoryHint: .isDirectory)
        let script = checkout.appending(path: "script/test_scope.sh")
        try write(rules, to: checkout.appending(path: "script/test-scope.json"))
        try FileManager.default.copyItem(at: repoURL("script/test_scope.sh"), to: script)
        try git(["init", "-q", "-b", "master"], in: checkout)
        return (checkout, script)
    }

    private func write(_ contents: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Keeps the developer's git settings, such as `diff.renames` or a global ignore file, out of the temp checkout.
    private static let isolatedGitConfig = [
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "core.excludesFile",
        "GIT_CONFIG_VALUE_0": "/dev/null"
    ]

    private func commitAll(_ message: String, in checkout: URL) throws {
        try git(["add", "-A"], in: checkout)
        try git(["commit", "-q", "-m", message], in: checkout)
    }

    private func git(_ arguments: [String], in checkout: URL) throws {
        let isolated = [
            "-C", checkout.path(percentEncoded: false),
            "-c", "user.name=Portu Tests", "-c", "user.email=tests@example.com",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"
        ]
        let result = try runScript(
            at: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: isolated + arguments,
            environment: Self.isolatedGitConfig)
        try #require(result.status == 0, "git \(arguments.joined(separator: " ")): \(result.error)")
    }
}

private enum Sandbox {
    static let noFileWrites = "(version 1)(allow default)(deny file-write*)(allow file-write* (literal \"/dev/null\"))"

    static let canApplyProfile: Bool = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1)(allow default)", "/usr/bin/true"]
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }()
}
