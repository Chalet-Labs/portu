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
        for file in try FileManager.default.contentsOfDirectory(atPath: testsDirectory.path(percentEncoded: false))
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
        let checkout = FileManager.default.temporaryDirectory
            .appending(path: "portu-test-scope-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: checkout) }
        let scriptDirectory = checkout.appending(path: "script", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scriptDirectory, withIntermediateDirectories: true)
        let script = scriptDirectory.appending(path: "test_scope.sh")
        try FileManager.default.copyItem(at: repoURL("script/test_scope.sh"), to: script)
        try write("""
        [
          { "glob": "committed/*", "groups": ["core"] },
          { "glob": "staged/*", "groups": ["network"] },
          { "glob": "unstaged/*", "groups": ["ui"] },
          { "glob": "untracked/*", "groups": ["app"] },
          { "glob": "moved-from/*", "groups": ["release"] },
          { "glob": "*", "groups": ["none"] }
        ]
        """, to: scriptDirectory.appending(path: "test-scope.json"))
        try write("unstaged before\n", to: checkout.appending(path: "unstaged/file.txt"))
        try write("moved file\n", to: checkout.appending(path: "moved-from/file.txt"))
        try git(["init", "-q", "-b", "master"], in: checkout)
        try git(["add", "-A"], in: checkout)
        try git(["commit", "-q", "-m", "base"], in: checkout)
        try git(["branch", "base"], in: checkout)

        try write("committed\n", to: checkout.appending(path: "committed/file.txt"))
        try git(["mv", "moved-from", "moved-to"], in: checkout)
        try git(["add", "-A"], in: checkout)
        try git(["commit", "-q", "-m", "change"], in: checkout)
        try write("staged\n", to: checkout.appending(path: "staged/file.txt"))
        try git(["add", "staged/file.txt"], in: checkout)
        try write("unstaged after\n", to: checkout.appending(path: "unstaged/file.txt"))
        try write("untracked\n", to: checkout.appending(path: "untracked/file.txt"))

        let result = try runScript(at: script, arguments: ["--base", "base"])

        #expect(result.status == 0, "\(result.error)")
        #expect(result.output.split(separator: "\n") == ["app", "core", "network", "release", "ui"])
    }

    @Test func `scope from an unknown base ref fails`() throws {
        let result = try runScript("script/test_scope.sh", arguments: ["--base", "refs/heads/no-such-test-scope-base"])

        #expect(result.status != 0)
    }

    private func selectedGroups(_ paths: [String], options: [String] = []) throws -> [String] {
        let result = try runScript(
            "script/test_scope.sh",
            arguments: options + ["--paths-from", "-"],
            input: paths.joined(separator: "\n"))
        #expect(result.status == 0, "\(result.error)")
        return result.output.split(separator: "\n").map(String.init)
    }

    private func write(_ contents: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    private func git(_ arguments: [String], in checkout: URL) throws {
        let isolated = [
            "-C", checkout.path(percentEncoded: false),
            "-c", "user.name=Portu Tests", "-c", "user.email=tests@example.com",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"
        ]
        let result = try runScript(at: URL(fileURLWithPath: "/usr/bin/git"), arguments: isolated + arguments)
        try #require(result.status == 0, "git \(arguments.joined(separator: " ")): \(result.error)")
    }
}
