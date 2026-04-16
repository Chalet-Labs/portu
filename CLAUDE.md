# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Portu is a native macOS SwiftUI crypto portfolio dashboard. Local-first, no backend, no telemetry. Aggregates holdings from Zapper, CoinGecko, and exchange APIs (Kraken, Binance, Coinbase).

## Build

The project uses XcodeGen. **Always run `just generate` after modifying `project.yml`** before building.

```
just generate        # XcodeGen → Portu.xcodeproj
just build           # Debug build
just release         # Release build
just test-packages   # SPM package tests (PortuCore, PortuNetwork, PortuUI)
just test            # Full Xcode scheme tests
just lint            # Lint all Swift files
just lint-fix        # Auto-fix lintable violations
just format          # Format all Swift files
just clean           # Clean build artifacts
just debug-run       # Build + launch with debug server
just debug-stop      # Stop the debug app
```

## Architecture

Three SPM packages with clean boundaries — **do not introduce cross-package imports that violate this layering**:

```
PortuUI (views, theme, components)
  └── PortuCore (models, DTOs, keychain, protocols)

PortuNetwork (API clients, providers, price service)
  └── PortuCore
```

The app target (`Sources/Portu/`) imports all three and contains features, app state, and sync orchestration.

## Swift & Concurrency

- **Swift 6.2** with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- PortuUI uses `defaultIsolation(MainActor.self)` — app target does NOT (incompatible with TCA)
- PortuNetwork providers are `actor` types (off-main-thread)
- DTOs and enums must be plain `Sendable` for cross-isolation safety
- SwiftData `@Model` types are implicitly `@MainActor`

## Testing

- Use **Swift Testing** (`import Testing`), not XCTest
- Syntax: `@Test`, `#expect()`, `#require()`, async test methods
- Use `@Suite(.serialized)` only when tests share mutable state — do not add plain `@Suite` without traits
- Tests live in each package's `Tests/` directory and `Tests/PortuTests/`

## TDD Rules

- NEVER write implementation code without a failing test first
- Run tests after every change — use XcodeBuildMCP when available
- Full cycle: RED (failing test) → GREEN (minimal implementation) → REFACTOR (clean up)
- No implementation plans with code snippets — tests ARE the spec
- When a test fails unexpectedly, diagnose before changing the test
- Run the FULL test suite before considering a behavior complete
- Read specs from `openspec/changes/` before generating tests
- Refactor only when tests are GREEN — never refactor and change behavior simultaneously

## Debug Server

A local HTTP debug server (`localhost:9999`) for runtime inspection. `#if DEBUG` guarded.

**When to use:** After implementing features or fixing bugs that change runtime state (SwiftData models, sync, prices, network). Build with `just debug-run`, verify with `/debug-verify`, stop with `just debug-stop`.

Endpoint categories: SwiftData state (accounts, positions, assets, snapshots), TCA state (sync status, prices), actions (trigger sync, invalidate prices), network log. Run `/debug-verify` for dynamic endpoint discovery and verification from source.

When adding new SwiftData models or network log endpoints, add them in `DebugEndpoints.swift`. When adding new TCA state or action routes, register them in `DebugServer.swift`.

## Code Style

- Views: `*View`, `*Sheet`, `*Sidebar`, `*Panel`
- Types: `*DTO`, `*Provider`, `*Service`, `*Error`
- State: `*State`, `*Status`
- Enums use descriptive names: `AccountKind`, `ExchangeType`, `PositionType`

## SwiftData Models

Models use cascade delete rules and inverse relationships. When adding new models, follow the existing pattern in `Packages/PortuCore/Sources/Models/`.

**Never use `#Predicate` with optional chaining through relationships** (e.g. `$0.position?.account?.isActive`). CoreData generates unsupported `TERNARY` SQL and crashes at runtime. Use `@Query` without a filter and filter in Swift instead.

## Formatting

SwiftFormat is used for code formatting. It runs automatically via hooks on file edits.
