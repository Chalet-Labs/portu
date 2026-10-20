# Testing

Which tests to run while working, and how changed paths map to test groups. `just test` (every app suite) and `just test-packages` (every package suite) stay available; PR CI runs the full unit suite.

## Recipes

| Recipe | Runs | Use it |
|---|---|---|
| `just test-app <Suite> [<Suite> ...]` | `xcodebuild test` with `-only-testing:PortuTests/<Suite>` for each suite | During TDD on app code (`Sources/Portu/`, `Tests/PortuTests/`) |
| `just test-app` | Every app suite except `ReleaseAutomationTests` | After a change that touches many app suites |
| `just test-pkg <Core\|Network\|UI> [filter]` | `swift test` in `Packages/Portu<pkg>`, with `--filter <filter>` when given | During TDD on package code |
| `just test-affected [base]` | The groups your changes select against `base` (default `origin/master`) | Before pushing, and before calling behavior complete |

`<Suite>` is the Swift Testing suite name, such as `OverviewFeatureTests`. Every release test is in the `ReleaseAutomationTests` suite, including the extensions in `ReleaseAutomation*.swift` and `LocalSigningSetupTests.swift`.

Measured on an M4 Pro (2026-10-20): `just test-app OverviewFeatureTests` takes 8–12s end to end after an app edit, about 2s of it for the test host; `just test-pkg Core EnumTests` takes about 4s; the `ReleaseAutomationTests` suite alone takes about 110s.

## Affected groups

`script/test_scope.sh` lists the groups that changed paths select. `just test-affected` passes it `--base <base>`, which covers `<base>...HEAD` plus staged, unstaged and untracked files. Then it runs:

- `test-pkg` for each selected package group (`core`, `network`, `ui`);
- one `xcodebuild test` when `app` or `release` is selected: every app suite, plus `-skip-testing:PortuTests/ReleaseAutomationTests` unless `release` is selected.

When nothing is selected it prints `no test groups affected by <base>...HEAD` and exits 0. Report that line as it is; no tests ran.

To see the groups for some paths without running anything:

```bash
printf 'Sources/Portu/Features/Overview/OverviewFeature.swift\n' | script/test_scope.sh --paths-from -
script/test_scope.sh --base origin/master
```

## Rules

`script/test-scope.json` is the source of truth; PR CI is to read the same file once #143 lands. Every entry whose glob matches a path adds its groups, and a path that matches no entry selects every group. Globs use bash `[[ $path == $glob ]]` matching, where `*` also matches `/`. `all` means `core network ui app release`. Each entry needs a non-empty `glob` and at least one group from `core`, `network`, `ui`, `app`, `release`, `all` and `none`; otherwise the selector exits with an error rather than selecting a group nothing runs.

| Path | Groups |
|---|---|
| `Packages/PortuCore/*` | core, network, ui, app |
| `Packages/PortuNetwork/*` | network, app |
| `Packages/PortuUI/*` | ui, app |
| `Sources/Portu/*`, `Tests/PortuTests/*` | app |
| Files release tests read: `.github/workflows/*`, `.gitignore`, `.releaserc.json`, `package.json`, `package-lock.json`, `Configs/*`, `README.md`, `docs/agents/production-signing.md`, `docs/agents/sparkle-adhoc-proof.md`, `script/*`, `scripts/*`, `Sources/Portu/Resources/Info.plist`, `Tests/Fixtures/ReleaseAutomation/*`, `Tests/PortuTests/ReleaseAutomation*.swift`, `Tests/PortuTests/LocalSigningSetupTests.swift` | release, on top of any other match |
| `project.yml`, `Portu.xcodeproj/*`, `*Package.swift`, `*Package.resolved`, `script/test-scope.json`, `script/test_scope.sh` | all |
| Other `docs/*`, `*.md`, `.claude/*`, `.agents/*`, `openspec/*` | none |
| Anything else | all |

When a release test starts reading a new repo file, add a `release` entry for it, and name any new file of the `ReleaseAutomationTests` suite `ReleaseAutomation*.swift`. The `TestScopeGuardTests` suite scans every file that declares `struct` or `extension ReleaseAutomationTests`. It fails when one of those files, or a path literal passed to `string(`, `jsonObject(`, `fileExists(`, `runScript(` or `repoURL(` in them, matches no `release` or `all` entry (it runs the selector with `--no-fallback`, so the select-everything fallback doesn't count). It sits outside `ReleaseAutomationTests` so that it runs with every unfiltered app run (`just test`, `just test-app` with no suites, `just test-affected`), including the ones that skip that suite. It only sees literals in the test files, not files that the scripts themselves read.

## Test host

The app suites run inside a test host. Since #140 the host is an empty app (`TestHostApp` in `Sources/Portu/App/PortuMain.swift`): no window, no store and no startup work, so a test run never opens or migrates `~/Library/Application Support/Portu/Portu.store`.
