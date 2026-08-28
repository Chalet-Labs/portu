#!/usr/bin/env bash
set -euo pipefail

# Issue #84 — fail-closed production signing gate.
#
# Runs inside the protected `production-signing` GitHub Actions environment
# before any feed publication. Fails without publishing when the production
# Ed25519 private key is missing, malformed, or does not pair with the public
# key embedded in release builds (project.yml Release configuration).
#
# The private seed is never written to stdout, stderr, or disk. On success the
# DERIVED PUBLIC KEY is printed (safe) and recorded as `public_key` in
# $GITHUB_OUTPUT when present.

EXPECTED_PUBLIC_KEY=""
PROJECT_CONFIG=""

usage() {
  echo "usage: $0 [--expected-public-key <base64>] [--project-config <path>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-public-key)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --expected-public-key requires a value" >&2
        usage
        exit 2
      fi
      EXPECTED_PUBLIC_KEY="$2"
      shift 2
      ;;
    --project-config)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --project-config requires a value" >&2
        usage
        exit 2
      fi
      PROJECT_CONFIG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "$PROJECT_CONFIG" ]]; then
  PROJECT_CONFIG="$ROOT_DIR/project.yml"
fi

if [[ ! -f "$PROJECT_CONFIG" ]]; then
  echo "error: project configuration not found at '$PROJECT_CONFIG'" >&2
  exit 2
fi

# 1. The key must come from the protected environment secret.
PRIVATE_SEED="${PORTU_SPARKLE_PRIVATE_KEY:-}"
if [[ -z "$PRIVATE_SEED" ]]; then
  echo "error: production signing key is missing from the protected environment; refusing to publish" >&2
  exit 2
fi
PRIVATE_SEED="$(printf '%s' "$PRIVATE_SEED" | tr -d '[:space:]')"
trap 'unset PRIVATE_SEED' EXIT

if ! DECODED_LEN="$({ printf '%s' "$PRIVATE_SEED" | /usr/bin/base64 -D | /usr/bin/wc -c | /usr/bin/tr -d '[:space:]'; } 2>/dev/null)" || [[ "$DECODED_LEN" != "32" ]]; then
  echo "error: production signing key is malformed (expected a base64-encoded 32-byte Ed25519 seed); refusing to publish" >&2
  exit 2
fi

# 2. Resolve the public key embedded in release builds.
if [[ -z "$EXPECTED_PUBLIC_KEY" ]]; then
  EXPECTED_PUBLIC_KEY="$(awk '
    $0 ~ /^        Release:$/ { in_release = 1; next }
    in_release && /^        [A-Za-z][A-Za-z0-9_]*:/ { in_release = 0 }
    in_release && index($0, "PORTU_UPDATE_PUBLIC_KEY:") > 0 {
      line = $0
      sub(/^.*PORTU_UPDATE_PUBLIC_KEY:[[:space:]]*"/, "", line)
      sub(/".*$/, "", line)
      print line
      found = 1
      exit
    }
    END { if (found != 1) exit 3 }
  ' "$PROJECT_CONFIG")" || {
    echo "error: could not read PORTU_UPDATE_PUBLIC_KEY from the Release configuration of '$PROJECT_CONFIG'" >&2
    exit 2
  }
fi

if ! EXPECTED_DECODED_LEN="$({ printf '%s' "$EXPECTED_PUBLIC_KEY" | /usr/bin/base64 -D | /usr/bin/wc -c | /usr/bin/tr -d '[:space:]'; } 2>/dev/null)" || [[ "$EXPECTED_DECODED_LEN" != "32" ]]; then
  echo "error: embedded release public key is malformed (expected a base64-encoded 32-byte Ed25519 key)" >&2
  exit 2
fi

# 3. The signing key must pair with the key clients trust.
DERIVED_PUBLIC_KEY="$(printf '%s\n' "$PRIVATE_SEED" | "$ROOT_DIR/scripts/derive_sparkle_public_key.swift")"

if [[ "$DERIVED_PUBLIC_KEY" != "$EXPECTED_PUBLIC_KEY" ]]; then
  echo "error: production signing key does not match the public key embedded in release builds; refusing to publish" >&2
  exit 1
fi

echo "Production signing key verified against the embedded release public key."
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'public_key=%s\n' "$DERIVED_PUBLIC_KEY" >> "$GITHUB_OUTPUT"
fi
echo "$DERIVED_PUBLIC_KEY"
