import Foundation
import Testing

struct ScopeStepCase: Sendable, CustomTestStringConvertible {
    let groups: [String]
    let skipAll: Bool
    let skipRelease: Bool

    var testDescription: String {
        groups.joined(separator: " ")
    }

    static let all = [
        ScopeStepCase(groups: ["none"], skipAll: true, skipRelease: false),
        ScopeStepCase(groups: ["app"], skipAll: false, skipRelease: true),
        ScopeStepCase(groups: ["app", "core", "network", "ui"], skipAll: false, skipRelease: true),
        ScopeStepCase(groups: ["release"], skipAll: false, skipRelease: false),
        ScopeStepCase(groups: ["app", "core", "network", "release", "ui"], skipAll: false, skipRelease: false)
    ]
}

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
        // The script also counts untracked and modified files, so it runs before generate rewrites the project.
        let generate = try #require(steps.firstIndex { Self.justRecipes(in: $0.text).contains("generate") })
        #expect(scope < generate)

        let test = try #require(steps.first { Self.justRecipes(in: $0.text).contains("test-without-building") })
        #expect(test.text.contains(
            "TEST_FILTERS: ${{ steps.scope.outputs.skip_release == 'true' && '-skip-testing:PortuTests/ReleaseAutomationTests' || '' }}"))
        #expect(test.value(of: "run") == "just test-without-building $TEST_FILTERS")
    }

    @Test(arguments: ScopeStepCase.all)
    func `scope step turns the selected groups into skip outputs`(_ scope: ScopeStepCase) throws {
        let step = try runScopeStep(selecting: scope.groups)

        #expect(step.status == 0, "\(step.error)")
        #expect(step.outputs == ["skip_all=\(scope.skipAll)", "skip_release=\(scope.skipRelease)"])
        #expect(step.selectorArguments == "--base origin/master")
        for group in scope.groups {
            #expect(step.summary.contains("- `\(group)`"), "summary doesn't list \(group)")
        }
    }

    @Test func `scope step fails without outputs when the selector fails`() throws {
        let step = try runScopeStep(selecting: nil)

        #expect(step.status != 0)
        #expect(step.outputs.isEmpty)
    }

    @Test(arguments: ["script/test_scope.sh", "script/test-scope.json", ".github/workflows/ci.yml"])
    func `scope step runs everything when the selector, its rules or the workflow change`(_ selectorFile: String) throws {
        let step = try runScopeStep(selecting: ["none"], changing: selectorFile)

        #expect(step.status == 0, "\(step.error)")
        #expect(step.outputs == ["skip_all=false", "skip_release=false"])
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
            #expect(!run.contains("${{"), "a run: block interpolates an expression into the shell source")
        }
        let scope = try #require(steps.first { $0.runs.contains { $0.contains("script/test_scope.sh") } })
        #expect(scope.text.contains("BASE_REF: ${{ github.base_ref }}"))
    }

    /// One step of a job's `steps:` list.
    private struct WorkflowStep {
        /// The step's lines without YAML comments, so a comment can't stand in for a key, and with the `- ` of
        /// its first line blanked so every key shares one indent. A `#` line inside a `run:` block is shell
        /// source and stays.
        let lines: [Substring]
        /// Every `run:` value: the rest of its line, plus the lines indented deeper than the key.
        let runs: [String]
        private let keyIndent: Int

        init(_ rawLines: [Substring]) {
            self.keyIndent = Self.indent(of: rawLines[0])
            var lines: [Substring] = []
            var runs: [String] = []
            var block: [Substring]?
            for line in rawLines {
                let content = line.drop { $0 == " " }
                if block != nil, content.isEmpty || Self.indent(of: line) > keyIndent {
                    block?.append(line)
                    lines.append(line)
                    continue
                }
                if let finished = block {
                    runs.append(finished.joined(separator: "\n"))
                    block = nil
                }
                if content.hasPrefix("#") {
                    continue
                }
                if content.hasPrefix("run:") {
                    block = [content.dropFirst("run:".count)]
                }
                lines.append(line)
            }
            if let finished = block {
                runs.append(finished.joined(separator: "\n"))
            }
            self.lines = lines
            self.runs = runs
        }

        var text: String {
            lines.joined(separator: "\n")
        }

        /// The value of a key of the step itself, such as `if` or `id`, not of a key nested under `with:` or `env:`.
        /// A key whose value starts on the next line gives the rest of its own line, so it still reads as present.
        func value(of key: String) -> String? {
            lines.lazy
                .filter { Self.indent(of: $0) == keyIndent }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0 == "\(key):" || $0.hasPrefix("\(key): ") }
                .map { $0.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces) }
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

    private struct ScopeStepRun {
        let status: Int32
        let error: String
        let outputs: [String]
        let summary: String
        let selectorArguments: String
    }

    /// Runs the shell body of `ci.yml`'s scope step with `BASE_REF=master`, in a checkout whose
    /// `script/test_scope.sh` prints `groups`, or fails when `groups` is nil. `changedFile`, if given,
    /// is committed on top of `origin/master`.
    private func runScopeStep(selecting groups: [String]?, changing changedFile: String? = nil) throws -> ScopeStepRun {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))
        let run = try #require(steps.first { $0.value(of: "id") == "scope" }?.runs.first)
        let lines = run.split(separator: "\n", omittingEmptySubsequences: false)
        try #require(lines.first?.trimmingCharacters(in: .whitespaces) == "|", "scope step isn't a run: | block")
        let body = lines.dropFirst()
        let indent = body.filter { !$0.allSatisfy { $0 == " " } }.map { $0.prefix { $0 == " " }.count }.min() ?? 0

        let root = FileManager.default.temporaryDirectory
            .appending(path: "portu-scope-step-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root.appending(path: "checkout", directoryHint: .isDirectory)
        let work = root.appending(path: "work", directoryHint: .isDirectory)
        let file = { (name: String) in work.appending(path: name).path(percentEncoded: false) }

        let selector = checkout.appending(path: "script/test_scope.sh")
        let selection = groups.map { "printf '%s\\n' \($0.joined(separator: " "))" } ?? "exit 1"
        try write("#!/bin/bash\nprintf '%s' \"$*\" > \"$SCOPE_ARGUMENTS\"\n\(selection)\n", to: selector)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: selector.path(percentEncoded: false))
        try git(["init", "-q", "-b", "master"], in: checkout)
        try commitAll("base", in: checkout)
        try git(["update-ref", "refs/remotes/origin/master", "HEAD"], in: checkout)
        if let changedFile {
            let changed = checkout.appending(path: changedFile)
            let contents = (try? String(contentsOf: changed, encoding: .utf8)) ?? ""
            try write(contents + "# changed\n", to: changed)
            try commitAll("change", in: checkout)
        }

        try write(body.map { $0.dropFirst(indent) }.joined(separator: "\n") + "\n", to: work.appending(path: "step.sh"))
        for name in ["output", "summary", "arguments"] {
            try write("", to: work.appending(path: name))
        }
        let result = try runScript(
            at: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "cd \"$0\" && exec /bin/bash -e \"$1\"", checkout.path(percentEncoded: false), file("step.sh")],
            environment: Self.isolatedGitConfig.merging([
                "BASE_REF": "master",
                "GITHUB_OUTPUT": file("output"),
                "GITHUB_STEP_SUMMARY": file("summary"),
                "SCOPE_ARGUMENTS": file("arguments")
            ]) { $1 })
        let contents = { (name: String) in try String(contentsOf: work.appending(path: name), encoding: .utf8) }
        return try ScopeStepRun(
            status: result.status,
            error: result.error,
            outputs: contents("output").split(separator: "\n").map(String.init),
            summary: contents("summary"),
            selectorArguments: contents("arguments"))
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
