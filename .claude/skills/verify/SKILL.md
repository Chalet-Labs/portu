---
name: verify
description: Run lint, tests, and build to verify changes are correct. Use after implementing features or fixing bugs.
---

Run the following verification steps in order. Stop at the first failure and report it.

1. **Lint** — run `just lint` to check for SwiftLint violations
2. **Affected tests** — run `just test-affected` to execute the package and app tests your changes can affect (see `docs/agents/testing.md`). If it prints `no test groups affected by <base>...HEAD`, no tests ran: report that line, not "tests passed"
3. **Build check** — run `just build` to verify the full app compiles

Report results concisely: which step passed/failed, and the relevant error if any.
