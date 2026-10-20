import Foundation
import Testing

extension ReleaseAutomationTests {
    private static let packageTestTargets = [
        (package: "PortuCore", target: "PortuCoreTests"),
        (package: "PortuNetwork", target: "PortuNetworkTests"),
        (package: "PortuUI", target: "PortuUITests")
    ]

    /// One `xcodebuild` build graph compiles the packages, the app and every test bundle once;
    /// a `swift test`, `just build` or `just test` step would compile them again.
    @Test func `ci workflow compiles the packages and the app once`() throws {
        let workflow = try string(".github/workflows/ci.yml")
        let recipes = Self.justRecipes(in: workflow)

        #expect(recipes.filter { $0 == "build-for-testing" }.count == 1)
        #expect(recipes.filter { $0 == "test-without-building" }.count == 1)
        let generate = try #require(recipes.firstIndex(of: "generate"))
        let build = try #require(recipes.firstIndex(of: "build-for-testing"))
        let test = try #require(recipes.firstIndex(of: "test-without-building"))
        #expect(generate < build)
        #expect(build < test)

        for recompiling in ["build", "test", "test-packages"] {
            #expect(!recipes.contains(recompiling), "ci.yml runs just \(recompiling)")
        }
        #expect(!workflow.contains("swift test"))
    }

    @Test func `scheme tests every package`() throws {
        let project = try string("project.yml")
        let scheme = try string("Portu.xcodeproj/xcshareddata/xcschemes/Portu.xcscheme")
        let testables = try #require(Self.section("Testables", in: scheme))
        let references = testables.components(separatedBy: "<TestableReference").dropFirst()

        for (package, target) in Self.packageTestTargets {
            #expect(project.contains("- package: \(package)/\(target)"))
        }
        let bundles = [(target: "PortuTests", container: "Portu.xcodeproj")]
            + Self.packageTestTargets.map { (target: $0.target, container: "Packages/\($0.package)") }
        for (target, container) in bundles {
            let reference = try #require(
                references.first { $0.contains("BlueprintName = \"\(target)\"") },
                "scheme doesn't test \(target)")
            #expect(reference.contains("skipped = \"NO\""), "scheme skips \(target)")
            #expect(reference.contains("ReferencedContainer = \"container:\(container)\""))
        }
    }

    /// The recipe of every `just` command, whether in a single-line `run:` step or a `run: |` block.
    private static func justRecipes(in workflow: String) -> [String] {
        workflow.split(separator: "\n").compactMap { line in
            var command = line.trimmingCharacters(in: .whitespaces)
            if command.hasPrefix("run: ") {
                command.removeFirst("run: ".count)
            }
            let words = command.split(whereSeparator: \.isWhitespace)
            guard words.count > 1, words[0] == "just" else { return nil }
            return String(words[1])
        }
    }

    private static func section(_ element: String, in xml: String) -> Substring? {
        guard
            let start = xml.range(of: "<\(element)>"),
            let end = xml.range(of: "</\(element)>", range: start.upperBound ..< xml.endIndex)
        else { return nil }
        return xml[start.upperBound ..< end.lowerBound]
    }
}
