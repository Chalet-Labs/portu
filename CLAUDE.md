# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Portu is a native macOS SwiftUI crypto portfolio dashboard. Local-first, no backend, no telemetry. Aggregates holdings from Zapper, CoinGecko, and exchange APIs (Kraken, Binance, Coinbase).

## Build

The project uses XcodeGen. **Always run `just generate` after modifying `project.yml`** before building.

```
just generate        # XcodeGen → Portu.xcodeproj
just build           # Debug build
just test-packages   # SPM package tests (PortuCore, PortuNetwork, PortuUI)
just test            # Full Xcode scheme tests
```

## Architecture

Three SPM packages with clean boundaries — **do not introduce cross-package imports that violate this layering**:

```
PortuUI (views, theme, components)
  └── PortuNetwork (API clients, providers, price service)
       └── PortuCore (models, DTOs, keychain, protocols)
```

The app target (`Sources/Portu/`) imports all three and contains features, app state, and sync orchestration.

## Swift & Concurrency

- **Swift 6.2** with strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- PortuUI and app target use `defaultIsolation(MainActor.self)`
- PortuNetwork providers are `actor` types (off-main-thread)
- DTOs and enums must be plain `Sendable` for cross-isolation safety
- SwiftData `@Model` types are implicitly `@MainActor`

## Testing

- Use **Swift Testing** (`import Testing`), not XCTest
- Syntax: `@Suite`, `@Test`, `#expect()`, `#require()`, async test methods
- Follow spec-driven TDD: behavioral spec → tests (RED) → implement → tests (GREEN)
- Tests live in each package's `Tests/` directory and `Tests/PortuTests/`

## Code Style

- Views: `*View`, `*Sheet`, `*Sidebar`, `*Panel`
- Types: `*DTO`, `*Provider`, `*Service`, `*Error`
- State: `*State`, `*Status`
- Enums use descriptive names: `AccountKind`, `ExchangeType`, `PositionType`

## SwiftData Models

Models use cascade delete rules and inverse relationships. When adding new models, follow the existing pattern in `Packages/PortuCore/Sources/Models/`.

## Formatting

SwiftFormat is used for code formatting. It runs automatically via hooks on file edits.
