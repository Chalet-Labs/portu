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

    @Test func `pull request ci scopes release tests through the rules script`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))
        let checkout = try #require(steps.first { $0.value(of: "uses")?.hasPrefix("actions/checkout@") == true })
        #expect(checkout.text.contains("fetch-depth: 0"), "origin/<base>...HEAD needs the base history")

        let scope = try #require(steps.firstIndex { $0.runs.contains { $0.contains("script/test_scope.sh") } })
        #expect(steps[scope].value(of: "id") == "scope")
        #expect(steps[scope].value(of: "if") == "github.event_name == 'pull_request'")
        let script = steps[scope].runs.joined(separator: "\n")
        for output in ["skip_all=", "skip_release=", "$GITHUB_OUTPUT", "$GITHUB_STEP_SUMMARY"] {
            #expect(script.contains(output), "scope step doesn't write \(output)")
        }
        // The script also counts untracked and modified files, so it runs before generate rewrites the project.
        let generate = try #require(steps.firstIndex { Self.justRecipes(in: $0.text).contains("generate") })
        #expect(scope < generate)

        let test = try #require(steps.first { Self.justRecipes(in: $0.text).contains("test-without-building") })
        #expect(test.text.contains("steps.scope.outputs.skip_release == 'true'"))
        #expect(test.text.contains("-skip-testing:PortuTests/ReleaseAutomationTests"))
    }

    @Test func `docs-only pull requests skip build and test`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))

        for recipe in ["build-for-testing", "test-without-building"] {
            let step = try #require(steps.first { Self.justRecipes(in: $0.text).contains(recipe) })
            // `!= 'true'`: a push to master has no scope step, so the output is empty and the step must still run.
            #expect(step.value(of: "if") == "steps.scope.outputs.skip_all != 'true'", "\(recipe) isn't skipped")
        }
        let lint = try #require(steps.first { Self.justRecipes(in: $0.text).contains("lint-strict") })
        #expect(lint.value(of: "if") == nil, "format and lint must always run")
    }

    @Test func `pull request base ref reaches the scope step only through env`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))

        for run in steps.flatMap(\.runs) {
            #expect(!run.contains("github.base_ref"), "a run: block interpolates the base ref")
        }
        let scope = try #require(steps.first { $0.runs.contains { $0.contains("script/test_scope.sh") } })
        #expect(scope.text.contains("BASE_REF: ${{ github.base_ref }}"))
        #expect(scope.runs.joined().contains("--base \"origin/$BASE_REF\""))
    }

    /// One step of a job's `steps:` list.
    private struct WorkflowStep {
        /// The step's lines, with the `- ` of its first line blanked so every key shares one indent.
        let lines: [Substring]

        var text: String {
            lines.joined(separator: "\n")
        }

        private var keyIndent: Int {
            Self.indent(of: lines[0])
        }

        /// The value of a key of the step itself, such as `if` or `id`, not of a key nested under `with:` or `env:`.
        func value(of key: String) -> String? {
            lines.lazy
                .filter { Self.indent(of: $0) == keyIndent }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix("\(key): ") }
                .map { String($0.dropFirst(key.count + 2)) }
        }

        /// Every `run:` value: the rest of its line, plus the lines indented deeper than the key.
        var runs: [String] {
            var blocks: [String] = []
            var block: [Substring]?
            for line in lines {
                let content = line.drop { $0 == " " }
                if block != nil, content.isEmpty || Self.indent(of: line) > keyIndent {
                    block?.append(line)
                    continue
                }
                if let finished = block {
                    blocks.append(finished.joined(separator: "\n"))
                    block = nil
                }
                if content.hasPrefix("run:") {
                    block = [content.dropFirst("run:".count)]
                }
            }
            if let finished = block {
                blocks.append(finished.joined(separator: "\n"))
            }
            return blocks
        }

        private static func indent(of line: Substring) -> Int {
            line.prefix { $0 == " " }.count
        }
    }

    /// The steps of the single job in `ci.yml`, split at the `- ` items of its `steps:` list.
    private static func ciSteps(in workflow: String) throws -> [WorkflowStep] {
        let lines = workflow.split(separator: "\n", omittingEmptySubsequences: false)
        let list = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "steps:" })
        let itemPrefix = String(repeating: " ", count: lines[list].prefix { $0 == " " }.count + 2) + "- "

        var steps: [[Substring]] = []
        for line in lines[(list + 1)...] {
            if line.hasPrefix(itemPrefix) {
                steps.append([Substring(String(repeating: " ", count: itemPrefix.count)) + line.dropFirst(itemPrefix.count)])
            } else if !steps.isEmpty {
                steps[steps.count - 1].append(line)
            }
        }
        return steps.map(WorkflowStep.init)
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
