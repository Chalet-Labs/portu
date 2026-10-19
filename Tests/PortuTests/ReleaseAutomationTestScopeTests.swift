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

    /// Release tests are skipped on PRs whose paths don't select `release`, so every repo file a release
    /// test reads must select it. Only literals in the test files are seen, not files the scripts read.
    @Test func `every path a release test reads selects the release group`() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let releaseTestFiles = try FileManager.default
            .contentsOfDirectory(atPath: testsDirectory.path(percentEncoded: false))
            .filter { name in
                (name.hasPrefix("ReleaseAutomation") && name.hasSuffix(".swift"))
                    || name == "LocalSigningSetupTests.swift"
            }
        let pathArgument = #/\b(?:string|jsonObject|fileExists|runScript|repoURL)\(\s*"((?:[^"\\]|\\.)*)"/#

        var paths = Set<String>()
        for file in releaseTestFiles {
            let source = try String(contentsOf: testsDirectory.appending(path: file), encoding: .utf8)
            for match in source.matches(of: pathArgument) {
                let literal = String(match.output.1)
                let staticPrefix = literal.components(separatedBy: "\\(").first ?? literal
                paths.insert(staticPrefix)
            }
        }

        #expect(paths.contains("scripts/publish_sparkle_appcast.sh"))
        #expect(paths.contains(".github/workflows/"))
        for path in paths.sorted() {
            #expect(try selectedGroups([path]).contains("release"), "\(path) is read by a release test")
        }
    }

    private func selectedGroups(_ paths: [String]) throws -> [String] {
        let input = paths.map { "\($0)\n" }.joined()
        let result = try runScript("script/test_scope.sh", arguments: ["--paths-from", "-"], input: input)
        #expect(result.status == 0, "\(result.error)")
        return result.output.split(separator: "\n").map(String.init)
    }
}
