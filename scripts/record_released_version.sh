#!/usr/bin/env bash
set -euo pipefail

# Records the version semantic-release just published (and the build-time
# digest of the DMG it produced) so the gated `publish-feed` job (protected
# `production-signing` environment) can sign exactly those bytes. The build
# job itself never touches the signing key, and the digest binds the later
# signing pass to the artifact the release job produced — GitHub Release
# assets are mutable, job outputs of this run are not.

VERSION="${1:-}"
DMG_PATH="${2:-}"

if [[ -z "$VERSION" ]]; then
  echo "error: released version is required" >&2
  exit 2
fi

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$VERSION" =~ $SEMVER_REGEX ]]; then
  echo "error: released version '$VERSION' is not a valid semantic version" >&2
  exit 2
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'released_version=%s\n' "$VERSION" >> "$GITHUB_OUTPUT"
fi
echo "Recorded released version $VERSION"

if [[ -n "$DMG_PATH" ]]; then
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: released DMG not found at '$DMG_PATH'" >&2
    exit 2
  fi
  DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
  if [[ ! "$DMG_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: could not compute SHA-256 digest for '$DMG_PATH'" >&2
    exit 2
  fi
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'dmg_sha256=%s\n' "$DMG_SHA256" >> "$GITHUB_OUTPUT"
  fi
  echo "Recorded DMG digest $DMG_SHA256"
fi
