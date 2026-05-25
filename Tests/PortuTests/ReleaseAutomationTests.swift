import Foundation
import Testing

struct ReleaseAutomationTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func `semantic release config publishes alpha GitHub release assets`() throws {
        let config = try jsonObject(".releaserc.json")

        #expect(config["branches"] as? [String] == ["master"])
        #expect(config["tagFormat"] as? String == "alpha-${version}")

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
        #expect(exec["publishCmd"] as? String == "scripts/mark_github_release_prerelease.sh ${nextRelease.gitTag}")
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
    }

    @Test func `release workflow runs tests then semantic release on push`() throws {
        let workflow = try string(".github/workflows/release.yml")

        #expect(workflow.contains("push:"))
        #expect(workflow.contains("branches: [master]"))
        #expect(workflow.contains("contents: write"))
        #expect(workflow.contains("npm ci"))
        #expect(workflow.contains("just generate"))
        #expect(workflow.contains("just build"))
        #expect(workflow.contains("just test-packages"))
        #expect(workflow.contains("just test"))
        #expect(workflow.contains("npx semantic-release"))
        #expect(workflow.contains("SEMANTIC_RELEASE_TOKEN"))
        #expect(workflow.contains("semantic-release-bot"))
    }

    @Test func `pull request title workflow enforces conventional squash titles`() throws {
        let workflow = try string(".github/workflows/pr-title.yml")

        #expect(workflow.contains("pull_request:"))
        #expect(workflow.contains("PR_TITLE: ${{ github.event.pull_request.title }}"))
        #expect(workflow.contains("feat|fix|perf|docs|test|tests|refactor|style|build|ci|chore|revert"))
        #expect(workflow.contains("PR title must use Conventional Commits"))
    }

    @Test func `release packaging scripts ad-hoc sign dmg and mark prereleases`() throws {
        let packageScript = try string("scripts/package_release_dmg.sh")
        let markScript = try string("scripts/mark_github_release_prerelease.sh")

        #expect(packageScript.contains("CODE_SIGN_IDENTITY=\"-\""))
        #expect(packageScript.contains("CODE_SIGNING_REQUIRED=NO"))
        #expect(packageScript.contains("MARKETING_VERSION=\"$VERSION\""))
        #expect(packageScript.contains("CURRENT_PROJECT_VERSION=\"$BUILD_NUMBER\""))
        #expect(packageScript.contains("hdiutil create"))
        #expect(packageScript.contains("hdiutil verify"))
        #expect(packageScript.contains("shasum -a 256"))
        #expect(packageScript.contains("CFBundleShortVersionString"))

        #expect(markScript.contains("gh release edit"))
        #expect(markScript.contains("--prerelease"))
    }

    @Test func `app version is supplied by xcode build settings`() throws {
        let infoPlist = try string("Sources/Portu/Resources/Info.plist")
        let project = try string("project.yml")

        #expect(infoPlist.contains("<string>$(MARKETING_VERSION)</string>"))
        #expect(infoPlist.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
        #expect(project.range(of: #"MARKETING_VERSION: "\d+\.\d+\.\d+""#, options: .regularExpression) != nil)
        #expect(project.range(of: #"CURRENT_PROJECT_VERSION: "\d+""#, options: .regularExpression) != nil)
    }

    private func string(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appending(path: path), encoding: .utf8)
    }

    private func jsonObject(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appending(path: path))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
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
