# Swift App TDD & AI-Assisted Development for Solopreneurs

*Research compiled 2026-03-29*

---

## Executive Summary

The convergence of Swift Testing (WWDC24), AI coding agents (Claude Code, Cursor), and structured build tooling (XcodeBuildMCP) has fundamentally changed the economics of test-driven development for solo iOS/macOS developers. TDD, once considered too expensive for indie devs, is now a **speed advantage** when paired with AI — tests-first prevents AI from writing plausible-but-broken code, and AI eliminates the tedium of writing boilerplate test/implementation code.

**The recommended stack for a solopreneur starting a new Swift app in 2026:**

| Layer | Recommendation | Why |
|-------|---------------|-----|
| Testing Framework | Swift Testing | Modern, async-native, parallel by default |
| Architecture | TCA or MVVM+Protocols | TCA for max testability; MVVM for lower learning curve |
| AI Agent | Claude Code | Best reasoning + agentic TDD via spec-driven workflow |
| Spec Tooling | OpenSpec | Structured behavioral specs, agent-agnostic, no vendor lock-in |
| TDD Discipline | CLAUDE.md rules + XcodeBuildMCP gates | Lightweight enforcement without plan overhead |
| Build Integration | XcodeBuildMCP | Structured Xcode build/test access for AI agents |
| Editor | Cursor (daily) + Xcode (builds/previews) | Cursor for AI-assisted editing; Xcode for native tooling |
| Snapshot Testing | Prefire + swift-snapshot-testing | Auto-generates snapshot tests from `#Preview` blocks |
| UI Testing | XCUITest with accessibility identifiers | Stable query surface that survives refactors |
| CI/CD | GitHub Actions + local Fastlane | One CI system; Xcode Cloud only needed for App Store distribution |
| Concurrency Reference | steipete's Swift Testing Playbook | Feed to AI agents as context for correct async patterns |

**Key insight:** The single highest-leverage action is writing detailed specs before prompting AI. Indragie Karunaratne shipped a 20,000-line macOS app with <1,000 hand-written lines — the quality differentiator was spec quality, not tool choice.

---

## Table of Contents

1. [Testing Frameworks: Swift Testing vs XCTest](#1-testing-frameworks)
2. [AI Coding Tools for Swift](#2-ai-coding-tools)
3. [XcodeBuildMCP: Structured Xcode Access for AI](#3-xcodebuildmcp)
4. [Specification-Driven Development (SDD) with AI Agents](#4-specification-driven-development)
5. [Architecture Patterns for Testability](#5-architecture-patterns)
6. [Snapshot & UI Testing](#6-snapshot--ui-testing)
7. [CI/CD for Solo Developers](#7-cicd)
8. [Swift Concurrency Testing](#8-concurrency-testing)
9. [Solopreneur-Specific Guidance](#9-solopreneur-guidance)
10. [Practical Daily Workflow](#10-daily-workflow)
11. [Conclusions & Recommendations](#11-conclusions)
12. [Sources & References](#12-sources)

---

## 1. Testing Frameworks

### Swift Testing vs XCTest

Swift Testing (introduced WWDC24) is the clear choice for new projects. XCTest remains necessary only for UI automation (`XCUIApplication`) and performance metrics (`XCTMetric`). Both frameworks coexist in the same test target.

| Feature | Swift Testing | XCTest |
|---------|--------------|--------|
| Syntax | `@Test` + `#expect` / `#require` macros | `testXXX()` methods + `XCTAssert*` functions |
| Structure | Structs, classes, actors | Must subclass `XCTestCase` |
| Concurrency | Built on Swift Concurrency | Bolt-on support via expectations |
| Parallelization | In-process via Swift Concurrency (default on) | Limited, multi-process |
| Traits | Rich: `.tags()`, `.enabled(if:)`, `.disabled()`, `.bug()` | Minimal |
| Failure Diagnostics | Auto-captures subexpression values | Manual message strings |
| Parameterized Tests | Native `@Test(arguments:)` | Manual loops |
| UI Testing | Not supported | XCUITest |
| Performance Testing | Not supported | XCTMetric |

### Migration Path

- New tests: Swift Testing exclusively
- Existing XCTest: Migrate incrementally; both run in the same target
- UI tests: Stay on XCTest (XCUITest) for now
- Performance tests: Stay on XCTest (XCTMetric) for now

### Key Swift Testing Patterns

```swift
// Basic test
@Test("User can update display name")
func updateDisplayName() {
    var user = User(name: "Alice")
    user.updateName("Bob")
    #expect(user.displayName == "Bob")
}

// Parameterized test
@Test("Valid email formats", arguments: [
    "user@example.com",
    "user+tag@example.com",
    "user@sub.domain.com"
])
func validEmail(_ email: String) {
    #expect(EmailValidator.isValid(email))
}

// Async test with confirmation
@Test func asyncEventFires() async {
    await confirmation("event sent") { confirmed in
        sut.onEvent = { _ in confirmed() }
        await sut.trigger()
    }
}

// Serialized suite (opt out of parallel execution)
@Suite(.serialized)
struct DatabaseTests {
    @Test func insertRecord() async { ... }
    @Test func queryRecords() async { ... }
}
```

---

## 2. AI Coding Tools for Swift

### Tool Comparison (2026)

| Tool | Swift Quality | Test Generation | Autonomous Work | Cost | Best For |
|------|--------------|-----------------|-----------------|------|----------|
| **Claude Code** | Excellent | Excellent | Yes (agentic) | Usage-based | Complex features, TDD workflows, architecture |
| **Cursor** | Good | Good | Semi (inline) | $20/mo | Daily editing, fast iteration |
| **GitHub Copilot** | Adequate | Weak | No | $10-19/mo | Enterprise compliance, simple completions |
| **Xcode AI** | Basic | Poor | No | Free (included) | Simple boilerplate, SwiftUI modifiers |

### Claude Code Strengths for Swift TDD
- Multi-step reasoning: can hold architecture context across red-green-refactor cycles
- Agentic workflow: runs `xcodebuild test`, reads failures, iterates autonomously
- Strong at generating Swift Testing code (with proper context)
- Pairs with Superpowers plugin for enforced TDD discipline

### Claude Code Weaknesses (per Indragie Karunaratne's case study)
- Struggles with complex Swift Concurrency patterns (actors, sendability)
- Weak on complex type expressions and generics
- Cannot autonomously debug without human-guided reproduction steps
- Quality degrades with vague specs — **detailed specs are the #1 input quality factor**

### Cursor for Swift
- Tight editor integration for fast iteration
- Good at inline completions and short-range edits
- Less capable than Claude Code for multi-file architectural changes
- Use alongside Xcode (Cursor for AI editing, Xcode for builds/previews/debugging)

### Xcode 16+ Built-in AI
- Predictive Code Completion: 2GB on-device model, Apple Silicon only
- Good at: SwiftUI boilerplate, repeated patterns
- Bad at: recommends deprecated APIs, suggests XCTest instead of Swift Testing
- Swift Assist (cloud-based): announced WWDC 2024, availability unclear
- Verdict: supplementary, not a primary AI tool

### Critical Add-on: SwiftUI Agent Skill
Paul Hudson's [swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill) teaches AI agents idiomatic SwiftUI patterns. Without it, agents produce functional but non-idiomatic SwiftUI. **Install this for any AI tool you use with SwiftUI.**

---

## 3. XcodeBuildMCP: Structured Xcode Access for AI

### Overview

[XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) (maintained by **Sentry**) is an MCP server that gives AI agents structured access to Xcode's build system. Instead of agents shelling out raw `xcodebuild` commands and parsing stdout, it exposes **78+ tools** as typed MCP endpoints with agent-friendly error reporting.

This is the missing piece that makes the TDD loop fully agentic: Claude Code writes a failing test → calls XcodeBuildMCP to run it → confirms failure → writes implementation → runs tests again → confirms green. No manual intervention.

### Platform Support

| Destination | Supported |
|---|---|
| iOS Simulator | Yes |
| iOS Device (physical) | Yes (requires code signing) |
| **macOS** | **Yes** |

Requires macOS 14.5+ and Xcode 16+.

### Capabilities

- **Build & Test** — build schemes, run test plans, get structured pass/fail results
- **Simulator Management** — boot, screenshot, gesture simulation
- **Device Deployment** — install and run on physical devices
- **LLDB Debugging** — set breakpoints, inspect state programmatically
- **Swift Package Manager** — resolve, add/remove dependencies
- **Project Scaffolding** — create new targets and schemes
- **Log Capture** — structured build logs and crash reports
- Skips macro validation (avoids Swift Macro build errors in agent workflows)

### Setup

```bash
# Install via Homebrew
brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp

# Or via npm
npm install -g xcodebuildmcp@latest
```

Add to your Claude Code MCP config (`.mcp.json`):
```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "xcodebuildmcp"
    }
  }
}
```

### Why XcodeBuildMCP vs Raw `xcodebuild`

| | Raw `xcodebuild` | XcodeBuildMCP |
|---|---|---|
| Error format | Raw stdout/stderr to parse | Structured, typed results |
| Context detection | Manual scheme/destination flags | Auto-detects from project |
| Test results | Parse xcresult bundles yourself | Parsed pass/fail per test |
| Simulator mgmt | Separate `xcrun simctl` commands | Integrated tools |
| Debugging | Not available via CLI | LLDB integration |
| Agent ergonomics | Poor (output-dependent) | Designed for agents |

### Gotchas

- **Sentry telemetry enabled by default** — opt out if that concerns you
- Physical device builds need code signing pre-configured
- Xcode 16+ only (no older Xcode support)
- Apple published official docs on [giving agentic tools access to Xcode](https://developer.apple.com/documentation/xcode/giving-agentic-coding-tools-access-to-xcode) — this is becoming a first-class workflow

### Sources

- [getsentry/XcodeBuildMCP GitHub](https://github.com/getsentry/XcodeBuildMCP)
- [XcodeBuildMCP Official Website](https://www.xcodebuildmcp.com/)
- [Apple Developer — Agentic Coding Tools Access to Xcode](https://developer.apple.com/documentation/xcode/giving-agentic-coding-tools-access-to-xcode)
- [Two MCP Servers Made Claude Code an iOS Build System](https://blakecrosley.com/blog/xcode-mcp-claude-code)

---

## 4. Specification-Driven Development (SDD) with AI Agents

### The Paradigm Shift: BDD → SDD

Traditional BDD (Behavior-Driven Development) has been rebranded as **Specification-Driven Development (SDD)** in the AI era (Thoughtworks, Martin Fowler 2025). The core shift: specs are no longer just documentation for humans — they're machine-readable contracts that AI agents consume to generate tests and implementations.

TDD + AI is synergistic because **tests-first prevents AI from cheating**. Without tests, AI writes plausible-looking broken code. With tests as the spec, the feedback loop is tight and deterministic.

### Spec-Driven TDD (Recommended Approach)

The optimal AI-assisted TDD workflow treats **tests as the only contract** and gives the AI maximum implementation freedom. No implementation plans with code snippets — they constrain the AI's solution space and create a false verification signal ("does code match the plan?" instead of "do tests pass?").

| Phase | What | Who | Gate |
|-------|------|-----|------|
| **1. Behavioral Spec** | Structured spec (OpenSpec or plain markdown) | Human | — |
| **2. Test Generation** | Convert spec → Swift Testing assertions | AI (human reviews) | Tests compile |
| **3. Verify RED** | Run tests, confirm they fail | XcodeBuildMCP | All new tests fail |
| **4. Implement** | AI writes code freely — no plan to follow, just tests to pass | AI (unconstrained) | — |
| **5. Verify GREEN** | Run tests, confirm they pass | XcodeBuildMCP | All tests pass + no regressions |
| **6. Review** | Human checks design quality, not plan compliance | Human | Approval |

**Why no implementation plan?**
- LLMs are strongest at exploration — pre-written code snippets in plans narrow the search space
- Plans become stale the moment the AI discovers a better approach
- The tests already encode the full behavioral contract
- "Does the code match the plan?" is the wrong question; "do the tests pass?" is the right one

### SDD Tooling Landscape (2026)

| Tool | Stars | Type | AI Integration | Swift Support | Best For |
|------|-------|------|---------------|---------------|----------|
| **[OpenSpec](https://github.com/Fission-AI/OpenSpec)** | 35k+ | Spec framework | Claude, Copilot, ChatGPT (20+ agents) | Language-agnostic | Solo devs, agent-agnostic workflow |
| **[Tessl](https://tessl.io/)** | N/A (SaaS) | Platform + Registry | Claude Code, Cursor, Copilot | Language-agnostic | Teams, API hallucination prevention |
| **[IIKit](https://github.com/intent-integrity-chain/kit)** | 27 | Verification chain | Claude Code, Codex, Gemini | Language-agnostic | Compliance, multi-agent integrity |
| **[GitHub Spec Kit](https://github.com/nicepkg/spec-kit)** | — | SDD workflow | Copilot, Claude Code, Gemini CLI | Language-agnostic | GitHub-native workflows |
| **VS Code Spec Mode** | Built-in | IDE feature | VS Code agents | Language-agnostic | VS Code users |
| **Amazon Kiro** | Closed | IDE | Built-in agent | Language-agnostic | AWS ecosystem, fastest onboarding |

### OpenSpec (Recommended for Solopreneurs)

[OpenSpec](https://openspec.dev/) (v1.2.0, Feb 2026, 35k+ stars) is the leading open-source SDD framework. It formalizes behavioral specs using EARS-style syntax (SHALL, MUST, SHOULD) with BDD structure (Given-When-Then scenarios).

**Why OpenSpec fits the solo Swift dev workflow:**
- **Agent-agnostic** — works with Claude Code, Cursor, Copilot, no vendor lock-in
- **No API keys or MCP required** — works through slash commands in existing tools
- **Iterative, not waterfall** — specs evolve through propose → refine → apply cycles
- **Structured format** — gives AI agents a consistent spec format to generate tests from, more reliable than freeform markdown

**Slash commands:**
- `/opsx:propose` — generate a spec proposal from a description
- `/opsx:apply` — apply spec to generate implementation artifacts (tests, code)

**Example OpenSpec flow with Claude Code:**
```
1. Human describes feature in natural language
2. /opsx:propose → OpenSpec generates structured behavioral spec
3. Human reviews/refines spec
4. AI generates Swift Testing tests from spec
5. XcodeBuildMCP verifies RED
6. AI implements freely
7. XcodeBuildMCP verifies GREEN
```

### Tessl Spec Registry (Not Useful for Swift)

[Tessl](https://tessl.io/) offers a **Spec Registry** (open beta, 10,000+ reusable specs) for external libraries, designed to prevent AI from hallucinating APIs. Good concept, but **the registry has zero Swift/iOS specs** — it's entirely JavaScript/npm and Python/PyPI focused. No SwiftUI, UIKit, Foundation, or any Swift package coverage exists.

**For Swift API hallucination prevention, use instead:**
- **steipete's Swift Testing Playbook** — correct async/concurrency patterns
- **SwiftUI Agent Skill** — idiomatic SwiftUI APIs
- **context7 MCP** — fetches current library documentation on demand
- **XcodeBuildMCP** — compiler errors catch hallucinated APIs immediately (the fastest feedback loop)

### Intent Integrity Chain / Kit (Niche)

[IIKit](https://github.com/intent-integrity-chain/kit) (v2.7.16) provides cryptographic verification that requirements weren't drifted during multi-agent implementation. Uses Gherkin `.feature` files locked before implementation — no self-validating parts.

**For solopreneurs:** Overkill. The verification chain is designed for compliance-heavy multi-agent scenarios. Only relevant if you're working in regulated industries (healthcare, finance) where requirement traceability is mandated.

### TDD Discipline via CLAUDE.md Rules

Regardless of which spec tool you choose, enforce TDD discipline through project rules:

```markdown
## TDD Rules (add to CLAUDE.md)

- NEVER write implementation code without a failing test first
- Run tests via XcodeBuildMCP after every change
- Tests must fail before implementing (RED), pass after (GREEN)
- No implementation plans with code snippets — tests ARE the spec
- When a test fails unexpectedly, diagnose before changing the test
- Run the FULL test suite before considering a behavior complete
- Read specs from specs/ directory before generating tests
```

The AI agent reads CLAUDE.md at session start and follows these as hard rules. XcodeBuildMCP provides the deterministic pass/fail gate.

### Why Spec-Driven Beats Plan-Based TDD

| | Plan-Based (e.g., Superpowers) | Spec-Driven (OpenSpec + tests) |
|---|---|---|
| **Implementation freedom** | Constrained by plan snippets | Unconstrained — tests are the only contract |
| **Verification signal** | "Does code match plan?" (subjective) | "Do tests pass?" (deterministic) |
| **Iteration cost** | Must update plan + code | Just iterate code until tests pass |
| **AI capability usage** | Underutilized (following a template) | Fully utilized (exploring solutions) |
| **Spec format** | Ad-hoc, embedded in plan | Structured (EARS/Given-When-Then) |
| **Overhead** | Seven-phase workflow, subagent orchestration | Spec → test → implement → verify |
| **Tooling required** | Superpowers plugin + config | OpenSpec + CLAUDE.md rules + XcodeBuildMCP |

### Legacy BDD Frameworks (Not Recommended)

**Quick/Nimble** — still maintained for Swift BDD (XCTest-based), but no AI agent integration and not designed for the SDD workflow. The Given-When-Then structure is valuable, but Quick adds unnecessary indirection when Swift Testing already supports clear, expressive tests natively.

**Cucumber/Gauge** — legacy BDD tools with no Swift-native support and no AI-native design. The Gherkin spec format influenced OpenSpec and IIKit, but the tools themselves are not worth adopting for new Swift projects.

### Superpowers (Alternative)

[Superpowers](https://github.com/obra/superpowers) (29,000+ GitHub stars, Anthropic marketplace Jan 2026) enforces TDD discipline via a seven-phase workflow with fresh subagents. Well-maintained but its plan-with-code-snippets approach over-constrains AI agents. The discipline enforcement is valuable; the planning overhead is not. Consider extracting only the discipline rules into CLAUDE.md and using OpenSpec for specs instead.

### TDAD (Test-Driven Agentic Development)

[arXiv:2603.17973](https://arxiv.org/html/2603.17973) (March 2026). Graph-based code-test impact analysis that maps dependencies between code and tests, telling the AI which tests to verify before committing. Empirically validated but **no Swift/Xcode implementation exists**. Academic contribution, not actionable today.

### Behavioral Spec Format (Without OpenSpec)

If you prefer not to adopt OpenSpec, a plain markdown behavioral spec works well. One behavior per bullet — no code:

```markdown
## Feature: Load Users

### Behaviors
- When loadUsers() is called, state transitions from idle → loading
- On successful API response, state transitions to loaded with user array
- On API failure, state transitions to error with the underlying error
- While loading, calling loadUsers() again is a no-op
- Empty API response results in loaded state with empty array

### Constraints
- Must use async/await (no Combine)
- Users must be sorted by displayName
- Network errors must be retried once before failing

### Edge Cases
- API returns malformed JSON → error state with decoding error
- Network timeout after 30s → error state
```

The AI reads this, generates Swift Testing tests for each behavior, verifies RED, then implements freely until GREEN.

---

## 5. Architecture Patterns for Testability

### Architecture Comparison for AI-Assisted TDD

| | TCA | MVVM + Protocols | MVVM + @Observable | Vanilla SwiftUI |
|---|---|---|---|---|
| **Testability** | Exhaustive (TestStore) | Good (protocol mocks) | Good (new patterns) | Poor |
| **AI Codegen Quality** | High (deterministic structure) | Medium (varies by design) | Medium | Low |
| **Learning Curve** | Steep | Low | Low-Medium | None |
| **Minimum iOS** | iOS 13 | iOS 13 | iOS 17 | iOS 13 |
| **Dependency Injection** | `@Dependency` macro | Manual protocols | Manual protocols | None |
| **Boilerplate** | Medium-High | Low | Low | None |

### TCA (The Composable Architecture)

**Why TCA is the most AI-friendly architecture for TDD:**

TCA's reducer structure is schema-deterministic — an AI agent given the architecture knows exactly where state changes happen and what to assert. The TestStore API enforces exhaustive assertions:

```swift
@Test func incrementCounter() async {
    let store = TestStore(initialState: Counter.State()) {
        Counter()
    }

    await store.send(.incrementTapped) {
        $0.count = 1  // Must assert ALL state changes
    }
}
```

Every unasserted state change or received action fails the test. This is friction for humans but gold for AI — the contract is explicit and complete.

**`@Dependency` for test isolation:**
```swift
// Production
@Dependency(\.apiClient) var apiClient

// Test
let store = TestStore(initialState: Feature.State()) {
    Feature()
} withDependencies: {
    $0.apiClient = .mock(returning: [User.preview])
}
```

**Trade-off:** TCA has a steep learning curve and is currently transitioning to v2.0 (deprecations began in v1.24-1.25). Solopreneurs adopting TCA today will face a migration.

**Current version:** v1.25.2 (March 16, 2025)

### MVVM + Protocols (Lower Learning Curve)

For solopreneurs who find TCA too heavy:

```swift
protocol UserServiceProtocol {
    func fetchUsers() async throws -> [User]
}

@Observable
class UsersViewModel {
    var state: ViewState<[User]> = .idle
    private let service: UserServiceProtocol

    init(service: UserServiceProtocol) { self.service = service }

    func loadUsers() async {
        state = .loading
        do {
            let users = try await service.fetchUsers()
            state = .loaded(users)
        } catch {
            state = .error(error)
        }
    }
}

// Test
@Test func loadUsersSuccess() async {
    let vm = UsersViewModel(service: MockUserService(users: [.preview]))
    await vm.loadUsers()
    #expect(vm.state == .loaded([.preview]))
}
```

AI can generate this pattern well, but the mock design varies — AI might produce inconsistent mock patterns across different ViewModels unless you provide a template.

### @Observable Testing (iOS 17+)

The Observation framework breaks `@Published`/Combine testing patterns. Key tool: Jacob Bartlett's [ObservationTestUtils](https://blog.jacobstechtavern.com/p/unit-test-the-observation-framework) package for eliminating boilerplate in observation-based tests.

### Recommendation

- **TCA** if you want maximum testability and are comfortable with the learning investment. Best for apps with complex state (financial, data-heavy).
- **MVVM + Protocols** if you want to start shipping fast with good-enough testability. Provide AI agents with a consistent mock template.
- **@Observable** for iOS 17+ only projects — but be aware the testing patterns are still maturing.

---

## 6. Snapshot & UI Testing

### Snapshot Testing Stack

**Prefire + swift-snapshot-testing** is the highest-leverage combination for solopreneurs:

[Prefire](https://github.com/BarredEwe/Prefire) (v5.4.0+) automatically converts `#Preview` blocks into snapshot tests via Swift Package Plugin. Zero extra test code — snapshot coverage comes free from previews you were writing anyway.

```swift
// Your preview (production code)
#Preview("User Card - Loaded") {
    UserCardView(user: .preview)
}

// Prefire auto-generates the snapshot test — no code needed
```

[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) (v1.17.x) is the underlying engine. Breaking API changes in recent versions:
- `isRecording` global → deprecated, use `withSnapshotTesting { }` configurator
- `diffTool` global → deprecated, use scoped configuration
- SwiftUI supported via `UIHostingController` wrapping

**CI consideration:** Xcode Cloud needs source file access to record baselines — baseline images must be committed to the repo.

### ViewInspector (Behavioral Testing)

[ViewInspector](https://github.com/nalexn/ViewInspector) tests SwiftUI view behavior (button taps, state changes) without rendering:

```swift
@Test func loginButtonDisabledWhenEmpty() throws {
    let view = LoginView()
    let button = try view.inspect().find(button: "Log In")
    #expect(button.isDisabled())
}
```

**Community consensus:** ViewInspector and snapshots are complementary:
- **Snapshots:** visual regression, layout/appearance
- **ViewInspector:** behavioral correctness, internal state assertions

### XCUITest Best Practices

For AI-assisted UI test generation, accessibility identifiers are non-negotiable:

```swift
// Production code
Button("Log In") { ... }
    .accessibilityIdentifier("login_button")

// Centralize identifiers
enum AccessibilityID {
    static let loginButton = "login_button"
    static let emailField = "email_field"
}

// UI test (stays stable across copy/localization changes)
let loginButton = app.buttons[AccessibilityID.loginButton]
loginButton.tap()
```

**Tips:**
- Centralize identifiers in one constants file (prevents string drift)
- Use `waitForExistence(timeout:)` — never `sleep()`
- Prefer `app.descendants(matching: .any)["identifier"]` over type-specific queries (more refactor-stable)
- Accessibility identifiers give AI agents a stable query surface

### Recommendation

1. Write `#Preview` blocks for all views (you should already be doing this)
2. Add Prefire to get free snapshot tests from previews
3. Use ViewInspector for behavioral assertions on complex interactive views
4. Use XCUITest with accessibility identifiers for critical user flows
5. Let AI generate XCUITest code from your accessibility identifier constants

---

## 7. CI/CD

### When to Use What

| Distribution Method | CI | Release Automation |
|---|---|---|
| **Mac App Store** | Xcode Cloud (tight App Store Connect integration) | Xcode Cloud or Fastlane |
| **Direct download / website / Homebrew** | GitHub Actions | Local Fastlane (sign, notarize, package) |
| **TestFlight only** | Either | Either |

**If you're not distributing through the App Store, Xcode Cloud adds nothing.** Its entire value proposition is App Store Connect integration. For direct distribution, GitHub Actions + Fastlane is simpler (one CI system, config as code, no GUI workflows).

### GitHub Actions (Recommended)

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          xcodebuild test \
            -scheme MyApp \
            -destination 'platform=macOS'
```

**Cost:** 2,000 free minutes/month, but macOS uses 10x multiplier → ~200 effective macOS minutes for private repos. At 8-15 min per CI run, that's 13-25 runs/month free. GitHub reduced pricing ~40% effective Jan 2026.

**For more headroom:** self-hosted runner on your Mac (free, unlimited minutes, faster builds since no cold start).

**Advantages over Xcode Cloud:**
- Config as code (YAML, version-controlled)
- Works with any distribution method
- Custom environments, Docker, Linux jobs if needed
- SPM packages testable in isolation
- Single CI system — no context switching

### Fastlane (Local Release Automation)

For macOS apps distributed outside the App Store, Fastlane handles the signing → building → notarizing → packaging pipeline:

```ruby
# Fastfile
lane :release do
  build_app(
    scheme: "MyApp",
    export_method: "developer-id"  # Not app-store
  )
  notarize(
    package: "MyApp.app",
    bundle_id: "com.you.myapp"
  )
  # Package as DMG, zip, or Homebrew cask
end
```

Run locally — human-initiated, not CI-triggered. Jesse Squires' recommendation for solo devs: **local Fastlane eliminates CI maintenance cost** while retaining the automation benefits for the release process itself.

### Xcode Cloud (Only If App Store)

**25 free hours/month** with Apple Developer Program ($99/year). Only worth it if you need:
- Automated TestFlight uploads
- App Store submission from CI
- App Store Connect integration (screenshots, metadata)

**Limitations that don't matter for direct distribution but do matter for everything else:**
- No version-controlled config (GUI only)
- App Store distribution only
- Standalone Swift Package targets can't be tested in isolation
- No custom environments

### Recommendation

**GitHub Actions for CI (tests on push) + local Fastlane for releases (sign, notarize, package).** One CI system, config as code, works for direct distribution. Skip Xcode Cloud entirely unless you add App Store distribution later.

---

## 8. Swift Concurrency Testing

### Async/Await Testing with Swift Testing

```swift
// Direct async testing — no expectations needed
@Test func fetchUserReturnsData() async throws {
    let service = UserService(client: MockHTTPClient())
    let user = try await service.fetchUser(id: "123")
    #expect(user.name == "Alice")
}
```

### Actor Testing

```swift
// Annotate test suite for MainActor isolation
@Suite(.serialized)
@MainActor
struct ViewModelTests {
    @Test func loadSetsState() async {
        let vm = UsersViewModel(service: MockService())
        await vm.load()
        #expect(vm.state == .loaded)
    }
}
```

**Key rule:** Annotate the entire test class/suite `@MainActor` for ViewModel tests. `Task.detached` inside tests does not inherit actor context — avoid it.

### Confirmation Pattern (Replaces XCTestExpectation)

```swift
@Test func delegateReceivesCallback() async {
    await confirmation("delegate called") { confirmed in
        let delegate = MockDelegate(onCall: { confirmed() })
        let sut = MyService(delegate: delegate)
        await sut.performAction()
    }
}
```

### Parallel Test Pitfalls

Swift Testing runs all tests in parallel by default. Common failures:
- Shared singleton mocks → random test failures
- Global state / UserDefaults access → data races
- File system operations → conflicts

**Fixes:**
- `@Suite(.serialized)` to opt out of parallelism
- `TaskLocal` for shared test context
- Per-test instance isolation (Swift Testing creates new `init()` per test function)

### Agent Context: steipete's Swift Testing Playbook

[Peter Steinberger's Swift Testing Playbook](https://gist.github.com/steipete/84a5952c22e1ff9b6fe274ab079e3a95) (updated Jun 2025) is explicitly designed as AI agent context material. **Feed this to Claude Code / Cursor as project context** — it covers all concurrency testing patterns in a format optimized for AI agents.

---

## 9. Solopreneur-Specific Guidance

### When TDD Pays Off (with AI)

| Scenario | TDD? | Why |
|----------|------|-----|
| Complex business logic (financial, data) | **Yes** | Correctness matters; AI excels at implementing to spec |
| Features requiring iteration/refactoring | **Yes** | Tests are the safety net for AI refactoring |
| MVP with changing requirements | **Yes** | Tests document intent; AI can pivot faster with them |
| Throwaway prototype (< 1 week) | **No** | Over-engineering; delete and rewrite is cheaper |
| Pure UI exploration / design iteration | **Snapshot only** | Full unit tests on layout code are waste |
| CRUD with no business logic | **Light** | Integration tests on the API layer, skip unit tests on thin wrappers |

### The ROI Flip

Traditional solo dev TDD economics: expensive upfront, pays back over months.

AI-assisted TDD economics:
- Test writing cost: **near-zero** (AI drafts from specs)
- Implementation cost: **near-zero** (AI writes to pass tests)
- Regression risk: **reduced** (test coverage enforced from the start)
- Net result: TDD becomes **cost-neutral or positive** versus cowboy coding, even for MVPs

### Time Investment Guide

| Activity | Without AI | With AI (Claude Code + Superpowers) |
|----------|-----------|--------------------------------------|
| Write test for one behavior | 10-30 min | 2-5 min |
| Implement to pass test | 15-60 min | 3-10 min |
| Refactor with test safety net | 10-30 min | 2-5 min |
| Full feature (5-10 behaviors) | 3-10 hours | 30-90 min |

### Common Solopreneur Mistakes

1. **Skipping specs** — The #1 quality factor is detailed specs before prompting. A 10-bullet spec takes 5 minutes and saves hours of AI misdirection.
2. **Testing implementation, not behavior** — Test what the code does, not how it does it. AI will change the "how" frequently.
3. **Over-testing UI** — Snapshot tests for visual regression; unit tests for behavior. Don't unit-test layout code.
4. **No architecture** — Vanilla SwiftUI with AI produces untestable spaghetti. Pick MVVM or TCA before writing any code.
5. **Ignoring AI limitations** — Claude Code struggles with complex Swift Concurrency and type expressions. Review these areas manually.

---

## 10. Practical Daily Workflow

### Recommended Setup

```
Xcode (previews, debugging, profiling)
  ↕
Cursor (AI-assisted editing, fast iteration)
  ↕
Claude Code CLI + XcodeBuildMCP (complex features, TDD workflows, builds/tests)
  ↕
Xcode Cloud (CI — runs tests on push)
```

### Feature Development Flow

```
1. SPEC (5 min) — Human writes, no code
   Option A: /opsx:propose → OpenSpec generates structured spec → refine
   Option B: Write plain markdown spec in specs/ directory
   Either way: behaviors, constraints, edge cases. No implementation details.

2. RED — AI generates tests from spec
   "Read the spec. Generate Swift Testing tests
    for each behavior. Do not write implementation."

   XcodeBuildMCP runs tests → all fail (expected).
   Human reviews test quality.

3. GREEN — AI implements freely
   "Make all tests pass. You have full freedom
    on implementation approach."

   XcodeBuildMCP runs tests → iterate until green.
   AI may try multiple approaches — that's the point.

4. VERIFY — Full suite
   XcodeBuildMCP runs ALL tests (not just new ones).
   No regressions allowed.

5. REVIEW — Human checks design quality
   Not "does it match a plan" — that doesn't exist.
   Does the code make sense? Is it maintainable?

6. SNAPSHOT (if UI work)
   Add #Preview blocks for new views.
   Prefire auto-generates snapshot tests.

7. COMMIT
   All tests green. Commit.
   Xcode Cloud picks up the push.
```

**Key difference from traditional TDD:** There is no implementation plan. The AI doesn't follow a blueprint — it explores solutions constrained only by the test suite. This uses the AI's strongest capability (exploration) instead of its weakest (following templates).

### Project Bootstrap Checklist

- [ ] Choose architecture (TCA or MVVM + Protocols)
- [ ] Set up Swift Testing target
- [ ] Add swift-snapshot-testing + Prefire as SPM dependencies
- [ ] Install XcodeBuildMCP (`brew tap getsentry/xcodebuildmcp && brew install xcodebuildmcp`)
- [ ] Configure XcodeBuildMCP in `.mcp.json`
- [ ] Set up OpenSpec (`/opsx:propose` workflow) or create `specs/` directory for plain markdown specs
- [ ] Add TDD rules to CLAUDE.md (see Section 4)
- [ ] Add steipete's Swift Testing Playbook to project context (`.claude/`)
- [ ] Add SwiftUI Agent Skill to project context
- [ ] Set up GitHub Actions workflow for tests on push (`.github/workflows/test.yml`)
- [ ] Create `AccessibilityID` constants file
- [ ] Set up Fastlane locally for release automation (sign, notarize, package)

---

## 11. Conclusions

### Key Findings

1. **Swift Testing is the standard** for new projects (2026). XCTest only for UI automation and performance tests.

2. **Specification-Driven Development (SDD) is the emerging paradigm** — BDD rebranded for the AI era. OpenSpec (35k+ stars) leads the open-source SDD tooling space with structured behavioral specs, agent-agnostic design, and no vendor lock-in. Tessl's Spec Registry (10k+ reusable library specs) complements by preventing API hallucination.

3. **Spec-driven TDD beats plan-based TDD** for AI-assisted development. Tests are the only contract; implementation plans with code snippets constrain the AI's solution space and create false verification signals. Behavioral specs + executable tests + maximum implementation freedom is the optimal workflow.

4. **Claude Code is the best AI tool** for Swift TDD workflows — but requires behavioral specs and Swift-specific context (steipete's playbook, SwiftUI agent skill). Give it freedom to explore, not a template to follow.

5. **TCA is the most AI-friendly architecture** for test generation due to its deterministic structure and exhaustive TestStore API. MVVM + Protocols is a pragmatic alternative with lower learning curve.

6. **XcodeBuildMCP closes the agentic loop** — gives Claude Code structured build/test access to Xcode, enabling fully autonomous red-green-refactor cycles. Supports iOS and macOS. Apple's official documentation on agentic Xcode access signals this is becoming a first-class workflow.

7. **Prefire is the highest-leverage testing tool** for solopreneurs — auto-generates snapshot tests from `#Preview` blocks you're already writing.

8. **GitHub Actions + local Fastlane** is the right CI/CD stack for non-App Store distribution. Xcode Cloud's value is App Store Connect integration — if you're distributing directly, it adds nothing. One CI system is simpler than two.

9. **TDD's economics flip with AI** — it becomes cost-neutral or positive even for MVPs, because AI eliminates the upfront cost of writing tests and implementations.

10. **Spec quality is the #1 factor** determining AI output quality. 5 minutes writing a behavioral spec saves hours of misdirection. Specs should describe behaviors and constraints, never implementation details.

### Open Questions & Active Debates

- **TCA v2.0 migration timeline** — unknown, but migration risk is low for solo AI-assisted devs: feed migration guide to Claude Code, let tests verify. The real TCA risk is learning curve — you must understand the architecture deeply enough to review AI output
- **Tessl Swift coverage** — RESOLVED: registry has zero Swift/iOS specs. JS/Python only. Not useful for Swift development. Use steipete's playbook, SwiftUI Agent Skill, and context7 MCP for API hallucination prevention instead
- **OpenSpec + Swift Testing integration** — RESOLVED: no case study needed; the components are straightforward to combine. Adopting this as the standard workflow
- **@Observable testing patterns** — RESOLVED: not relevant when using TCA; TestStore handles state observation. Only matters for MVVM with direct ViewModel testing
- **Test impact analysis for Swift** — TDAD has no Swift implementation. [XcodeSelectiveTesting](https://github.com/mikeger/XcodeSelectiveTesting) (v0.14.5, 274 stars) uses dependency-graph traversal to skip unaffected tests (~50% reduction), but requires modular multi-target projects and Swift Testing support is unconfirmed. Datadog offers coverage-based impact analysis but requires paid account. Revisit XcodeSelectiveTesting when: test suite >60s, project is modularized, and Swift Testing support is confirmed

### What This Research Did NOT Cover

- SwiftData testing patterns
- CloudKit / server-side Swift testing
- Accessibility audit testing (beyond identifiers)
- Performance testing and benchmarking
- Multi-platform (macOS, watchOS, visionOS) testing considerations

---

## 12. Sources & References

### Official Documentation
- [Meet Swift Testing — WWDC24](https://developer.apple.com/videos/play/wwdc2024/10179/)
- [Apple Developer — Giving Agentic Coding Tools Access to Xcode](https://developer.apple.com/documentation/xcode/giving-agentic-coding-tools-access-to-xcode)
- [Apple Xcode Cloud Documentation](https://developer.apple.com/xcode-cloud/)
- [GitHub Actions Runner Pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)

### SDD & Spec Tooling
- [OpenSpec](https://github.com/Fission-AI/OpenSpec) — Fission AI, v1.2.0, 35k+ stars, agent-agnostic SDD framework
- [OpenSpec Documentation](https://openspec.dev/) — official docs and guides
- [Tessl](https://tessl.io/) — Agent enablement platform with Spec Registry (10k+ reusable library specs)
- [Tessl Spec-Driven Development Guide](https://docs.tessl.io/use/spec-driven-development-with-tessl)
- [IIKit](https://github.com/intent-integrity-chain/kit) — Intent Integrity Chain, cryptographic requirement verification

### Tools & Libraries
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — Point-Free, v1.17.x
- [Prefire](https://github.com/BarredEwe/Prefire) — v5.4.0+, auto-snapshot from previews
- [ViewInspector](https://github.com/nalexn/ViewInspector) — SwiftUI behavioral testing
- [TCA](https://github.com/pointfreeco/swift-composable-architecture) — v1.25.2
- [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) — Sentry, structured Xcode access for AI agents
- [Superpowers](https://github.com/obra/superpowers) — TDD enforcement for Claude Code (alternative)
- [SwiftUI Agent Skill](https://github.com/twostraws/swiftui-agent-skill) — Paul Hudson
- [steipete's Swift Testing Playbook](https://gist.github.com/steipete/84a5952c22e1ff9b6fe274ab079e3a95)
- [ObservationTestUtils](https://blog.jacobstechtavern.com/p/unit-test-the-observation-framework) — Jacob Bartlett

### Articles & Blog Posts
- [Swift Testing vs XCTest Comparison](https://blogs.infosys.com/digital-experience/mobility/swift-testing-vs-xctest-a-comprehensive-comparison.html) — Infosys
- [Modern Swift Unit Testing](https://viesure.io/modern-swift-unit-testing/developer/) — Viesure
- [Claude Code vs Cursor vs GitHub Copilot 2026](https://dev.to/alexcloudstar/claude-code-vs-cursor-vs-github-copilot-the-2026-ai-coding-tool-showdown-53n4) — DEV Community
- [AI Coding Assistants 2026](https://medium.com/@saad.minhas.codes/ai-coding-assistants-in-2026-github-copilot-vs-cursor-vs-claude-which-one-actually-saves-you-4283c117bf6b) — Medium
- [I Shipped a macOS App Built Entirely by Claude Code](https://www.indragie.com/blog/i-shipped-a-macos-app-built-entirely-by-claude-code) — Indragie Karunaratne
- [Fastlane for Indies](https://www.jessesquires.com/blog/2024/01/22/fastlane-for-indies/) — Jesse Squires
- [AI Features in Xcode 16 Review](https://www.swiftwithvincent.com/blog/ai-features-in-xcode-16-is-it-good) — Vincent Pradeilles
- [Launched an iOS App in 2 Weeks with Claude AI](https://www.indiehackers.com/post/launched-an-ios-app-preppr-from-scratch-in-2-weeks-and-150-with-claude-ai-61c5342973) — Indie Hackers

### Research Papers
- [TDAD: Test-Driven Agentic Development](https://arxiv.org/html/2603.17973) — arXiv, March 2026

### Community Resources
- [AI Agents, Meet Test Driven Development](https://www.latent.space/p/anita-tdd) — Latent Space (Anita Jha)
- [Test-Driven Development with AI](https://www.builder.io/blog/test-driven-development-ai) — Builder.io
- [Unit Testing Async/Await](https://www.avanderlee.com/concurrency/unit-testing-async-await/) — SwiftLee
- [XCUITest UI Testing SwiftUI](https://www.swiftyplace.com/blog/xcuitest-ui-testing-swiftui) — SwiftyPlace
- [TCA on InfoQ](https://www.infoq.com/news/2024/08/swift-composable-architecture/) — InfoQ
- [Martin Fowler: Exploring SDD Tools](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html) — Martin Fowler
- [Thoughtworks: SDD as 2025 Practice](https://www.thoughtworks.com/en-us/insights/blog/agile-engineering-practices/spec-driven-development-unpacking-2025-new-engineering-practices) — Thoughtworks
- [Spec-Driven Development in 2025](https://www.softwareseni.com/spec-driven-development-in-2025-the-complete-guide-to-using-ai-to-write-production-code/) — SoftwareSeni
- [OpenSpec Deep Dive](https://redreamality.com/garden/notes/openspec-guide/) — Redreamality
