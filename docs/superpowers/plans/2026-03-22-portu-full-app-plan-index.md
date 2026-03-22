# Portu Full App Plan Index

**Spec:** `docs/superpowers/specs/2026-03-21-portu-full-app-design.md`

**Plan Set Date:** 2026-03-22

## Required Sequence

1. `docs/superpowers/plans/2026-03-22-portu-data-foundation.md`
2. `docs/superpowers/plans/2026-03-22-portu-overview-navigation.md`

## Parallelizable After Overview

- `docs/superpowers/plans/2026-03-22-portu-accounts.md`
- `docs/superpowers/plans/2026-03-22-portu-all-assets.md`
- `docs/superpowers/plans/2026-03-22-portu-performance.md`
- `docs/superpowers/plans/2026-03-22-portu-exposure.md`

## Follow-On Constraints

- `docs/superpowers/plans/2026-03-22-portu-all-positions.md`
  Run after Accounts if you want manual-account creation available before manual-position entry.

- `docs/superpowers/plans/2026-03-22-portu-asset-detail.md`
  Run after All Assets so row taps already exist and the feature can land on a real entry point immediately.

## Why The Split Looks Like This

- The spec’s Phase 1 is one shared foundation and must stay single-threaded.
- The spec’s Phase 2 is the validation slice for the new data model and navigation shell.
- The spec’s Phase 3 lists independent feature areas, so each one gets its own worker-sized plan instead of one oversized document.
