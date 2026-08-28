# Production Update Signing

How Portu signs production Sparkle updates without any paid Apple credential.
This is the production counterpart to the credential-free ad-hoc rehearsal flow
in `sparkle-adhoc-proof.md`.

## Trust model

- The Ed25519 private seed is the single production trust anchor. It is
  generated outside CI by the maintainer and exists in exactly two places: the
  protected `production-signing` GitHub Actions environment secret
  (`PORTU_SPARKLE_PRIVATE_KEY`) and an encrypted offline backup.
- Release builds embed only the public key (`PORTU_UPDATE_PUBLIC_KEY` in the
  `Release` configuration of `project.yml`). Clients verify every archive
  signature against it before extraction
  (`SUVerifyUpdateBeforeExtraction` = YES).
- Apple code signing remains ad hoc (`CODE_SIGN_IDENTITY="-"`). No Developer
  ID, notarization, or provisioning profile is involved.

## Release boundary

`release.yml` splits publication into two jobs:

1. `release` — builds, tests, and publishes the GitHub Release (DMG + SHA-256 +
   notes) via semantic-release. It holds no signing credential and needs no
   approval. It records the released version for the gated job.
2. `publish-feed` — declares `environment: production-signing` (required
   reviewer + branch policy `master`/`alpha`). After human approval it
   downloads the release DMG, runs `scripts/verify_production_signing.sh`
   (fails closed on a missing, malformed, or non-matching key), and only then
   publishes the signed appcast to the `updates` branch with the release notes
   embedded as signed feed metadata.

A failure in the gated job leaves the GitHub Release and the previous appcast
untouched; re-run it with the workflow's `retry_version` input. Pull requests
and helper agent workflows can never reach the secret: environment secrets
resolve only inside jobs that declare the environment, from allowed branches.

## Generating the key pair (maintainer, outside CI)

```bash
umask 077
openssl rand -base64 32 | tr -d '\n' > ~/.portu-production-ed25519.key
scripts/derive_sparkle_public_key.swift < ~/.portu-production-ed25519.key
```

Paste the printed public key into `project.yml` (`Release` →
`PORTU_UPDATE_PUBLIC_KEY`) and add the seed as the
`PORTU_SPARKLE_PRIVATE_KEY` environment secret. Never paste the private seed
into the repository, an issue, a PR, or a chat.

## Backup and recovery rehearsal (required before first production release)

1. Encrypt the seed offline (`age -r <recipient> -o portu-production-ed25519.key.age
   ~/.portu-production-ed25519.key`) and store it outside GitHub.
2. Complete a recovery rehearsal: from the offline copy alone, decrypt the
   seed, re-derive the public key with `scripts/derive_sparkle_public_key.swift`,
   and confirm it equals the key embedded in `project.yml`. Confirm the
   decrypted seed is accepted by `scripts/verify_production_signing.sh` with
   `--expected-public-key`. Delete every intermediate copy.
3. Only after the rehearsal passes, delete the plaintext key from the
   maintainer machine — the GitHub secret plus the verified backup remain.

## Key loss

If the private seed is lost and no tested offline backup exists:

- Treat it as a manual-bootstrap event. Never publish an unsigned update, a
  relaxed-verification feed, or an in-app recovery that bypasses Ed25519
  verification — losing the key must never weaken the update boundary.
- Generate a fresh key pair (outside CI), embed the new public key in
  `project.yml`, and ship a manual-bootstrap release. Because existing
  installs only trust the old public key, they cannot update in app; users
  download the new release manually from the GitHub releases page. Rotate the
  environment secret to the new seed and archive the old feed history.

## Verification checkpoints

- `scripts/verify_production_signing.sh` — fail-closed pre-publication gate.
- `scripts/generate_sparkle_appcast.sh --expected-public-key <base64>` —
  verifies the archive signature under the public key clients embed, not just
  under the signing seed.
- `scripts/assert_secret_absent.py` — the gated job scans its artifacts for
  the secret value after publication.
- `tests/PortuTests/ReleaseAutomationProductionSigningTests.swift` — keeps the
  boundary enforced: environment gating, secret isolation, and fail-closed
  behavior.
