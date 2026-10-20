import Foundation
import Testing

extension ReleaseAutomationTests {
    @Test func `ci restores the build cache before building`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))

        let restore = try #require(steps.firstIndex { Self.uses($0, "actions/cache/restore") })
        let build = try #require(steps.firstIndex { Self.justRecipes(in: $0.text).contains("build-for-testing") })
        #expect(restore < build)
        #expect(Self.input("path", of: steps[restore]) == ".build")
        // The combined action saves at the end of every run, PRs included, and never when its key hits exactly.
        #expect(!steps.contains { Self.uses($0, "actions/cache") })
    }

    @Test func `ci gives sources their commit times between generate and build`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))

        let restoreTimes = try #require(steps.firstIndex { $0.runs.contains { $0.contains("git restore-mtime") } })
        let generate = try #require(steps.firstIndex { Self.justRecipes(in: $0.text).contains("generate") })
        let build = try #require(steps.firstIndex { Self.justRecipes(in: $0.text).contains("build-for-testing") })
        // After generate, which rewrites the tracked project file.
        #expect(generate < restoreTimes && restoreTimes < build)
        #expect(steps[restoreTimes].value(of: "if") == "steps.scope.outputs.skip_all != 'true'")
    }

    /// Where `brew install git-tools` puts it. CI installs it before the tests run.
    private static let restoreMtime = ["/opt/homebrew/bin", "/usr/local/bin"]
        .map { "\($0)/git-restore-mtime" }
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    @Test(.enabled(if: restoreMtime != nil, "needs git-restore-mtime: brew install git-tools"))
    func `restore-mtime step stamps a pull request's files with its merge commit`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))
        let command = try #require(steps.first { $0.runs.contains { $0.contains("git restore-mtime") } }?.value(of: "run"))
        let tool = try #require(Self.restoreMtime)

        let checkout = FileManager.default.temporaryDirectory
            .appending(path: "portu-restore-mtime-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: checkout) }
        let base = 1_700_000_000
        try write("1\n2\n3\n4\n5\n", to: checkout.appending(path: "both.swift"))
        try write("master\n", to: checkout.appending(path: "master.swift"))
        try write("untouched\n", to: checkout.appending(path: "untouched.swift"))
        try git(["init", "-q", "-b", "master"], in: checkout)
        try commitAll("base", at: base, in: checkout)
        try git(["checkout", "-q", "-b", "pr"], in: checkout)
        try write("pr\n2\n3\n4\n5\n", to: checkout.appending(path: "both.swift"))
        try commitAll("pr", at: base + 100, in: checkout)
        // Master edits the PR's file later than the PR did, so its last commit on any parent is master's.
        try git(["checkout", "-q", "master"], in: checkout)
        try write("1\n2\n3\n4\nmaster\n", to: checkout.appending(path: "both.swift"))
        try write("master, edited\n", to: checkout.appending(path: "master.swift"))
        try commitAll("master", at: base + 200, in: checkout)
        // Like GitHub's refs/pull/N/merge: the base is the first parent.
        try git(["merge", "-q", "--no-ff", "-m", "merge", "pr"], in: checkout, environment: Self.commitDate(base + 300))

        let result = try runScript(
            at: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "cd \"$0\" && \(command)", checkout.path(percentEncoded: false)],
            environment: Self.isolatedGitConfig.merging([
                "PATH": "\(URL(fileURLWithPath: tool).deletingLastPathComponent().path(percentEncoded: false)):/usr/bin:/bin"
            ]) { $1 })
        #expect(result.status == 0, "\(result.error)")

        let mtime = { (name: String) in
            try (FileManager.default.attributesOfItem(atPath: checkout.appending(path: name).path(percentEncoded: false))[.modificationDate]
                as? Date)?.timeIntervalSince1970
        }
        // Master's own time would match the cache built from master's version, and the merged file would be skipped.
        #expect(try mtime("both.swift") == TimeInterval(base + 300))
        #expect(try mtime("master.swift") == TimeInterval(base + 200))
        #expect(try mtime("untouched.swift") == TimeInterval(base))
    }

    @Test func `ci builds with the default toolchain only`() throws {
        let workflow = try string(".github/workflows/ci.yml")
        let job = try #require(workflow.components(separatedBy: "\n    steps:\n").first)

        // The Metal toolchain's per-machine mount path relinked every product and recompiled every macro user.
        #expect(job.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces) == "TOOLCHAINS: com.apple.dt.toolchain.XcodeDefault"
        })
    }

    @Test func `only pushes to the default branch save the build cache, after the tests pass`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))

        let saves = steps.indices.filter { Self.uses(steps[$0], "actions/cache/save") }
        #expect(saves.count == 1)
        let save = try #require(saves.first)
        let test = try #require(steps.firstIndex { Self.justRecipes(in: $0.text).contains("test-without-building") })
        #expect(test < save)
        // No always() or failure(): a failed or cancelled build isn't saved.
        #expect(steps[save].value(of: "if")
            == "github.event_name == 'push' && github.ref == 'refs/heads/master' && steps.cache.outputs.cache-hit != 'true'")
        #expect(Self.input("path", of: steps[save]) == ".build")
    }

    @Test func `the saved key is per commit and the restored prefix is not`() throws {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))
        let keyStep = try #require(steps.firstIndex { $0.value(of: "id") == "cache-key" })
        let restoreStep = try #require(steps.firstIndex { Self.uses($0, "actions/cache/restore") })
        // Before the restore: the restored .build holds the checkouts' own Package.swift files, which hashFiles would match.
        #expect(keyStep < restoreStep)
        let restore = steps[restoreStep]
        let save = try #require(steps.first { Self.uses($0, "actions/cache/save") })

        let sha = "${{ github.sha }}"
        let saveKey = try #require(Self.input("key", of: save))
        let restoreKeys = try #require(Self.input("restore-keys", of: restore))
        #expect(restoreKeys == "${{ steps.cache-key.outputs.prefix }}")
        #expect(saveKey.hasSuffix(sha))
        #expect(saveKey == restoreKeys + sha, "a PR restores the newest master entry of the same prefix")
        // The same key on both sides, so a re-run's exact hit is what skips the save.
        #expect(Self.input("key", of: restore) == saveKey)
        #expect(restore.value(of: "id") == "cache")
        let dependencies = try #require(Self.input("DEPENDENCIES", of: steps[keyStep]))
        #expect(dependencies.hasPrefix("${{ hashFiles('**/Package.swift'"))
    }

    @Test func `cache key prefix names the xcode build and the dependency hash`() throws {
        let step = try runCacheKeyStep(xcodeVersion: "Xcode 26.3\nBuild version 17C529\n")

        #expect(step.status == 0, "\(step.error)")
        #expect(step.outputs == ["prefix=build-macOS-xcode-17C529-0123abcd-"])
    }

    @Test func `cache key step fails without an xcode build version`() throws {
        // Otherwise every Xcode would share one prefix and restore another Xcode's build products.
        let step = try runCacheKeyStep(xcodeVersion: "")

        #expect(step.status != 0)
        #expect(step.outputs.isEmpty)
    }

    private func commitAll(_ message: String, at time: Int, in checkout: URL) throws {
        try git(["add", "-A"], in: checkout)
        try git(["commit", "-q", "-m", message], in: checkout, environment: Self.commitDate(time))
    }

    private static func commitDate(_ time: Int) -> [String: String] {
        ["GIT_AUTHOR_DATE": "@\(time) +0000", "GIT_COMMITTER_DATE": "@\(time) +0000"]
    }

    private static func uses(_ step: WorkflowStep, _ action: String) -> Bool {
        step.value(of: "uses")?.hasPrefix("\(action)@") == true
    }

    /// The value of a `with:` input of a step that has no `run:` block.
    private static func input(_ name: String, of step: WorkflowStep) -> String? {
        step.lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(name): ") }
            .map { String($0.dropFirst(name.count + 2)) }
    }

    /// Runs the shell body of `ci.yml`'s cache key step with `xcodebuild` stubbed to print `xcodeVersion`.
    private func runCacheKeyStep(xcodeVersion: String) throws -> (status: Int32, error: String, outputs: [String]) {
        let steps = try Self.ciSteps(in: string(".github/workflows/ci.yml"))
        let run = try #require(steps.first { $0.value(of: "id") == "cache-key" }?.runs.first)

        let root = FileManager.default.temporaryDirectory
            .appending(path: "portu-cache-key-step-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        let xcodebuild = bin.appending(path: "xcodebuild")
        try write("#!/bin/bash\nprintf '%s' '\(xcodeVersion)'\n", to: xcodebuild)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: xcodebuild.path(percentEncoded: false))
        let script = root.appending(path: "step.sh")
        try write(Self.shellSource(of: run), to: script)
        let output = root.appending(path: "output")
        try write("", to: output)

        let result = try runScript(
            at: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-e", script.path(percentEncoded: false)],
            environment: [
                "PATH": "\(bin.path(percentEncoded: false)):/usr/bin:/bin",
                "RUNNER_OS": "macOS",
                "DEPENDENCIES": "0123abcd",
                "GITHUB_OUTPUT": output.path(percentEncoded: false)
            ])
        let outputs = try String(contentsOf: output, encoding: .utf8).split(separator: "\n").map(String.init)
        return (result.status, result.error, outputs)
    }
}
