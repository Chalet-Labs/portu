#!/usr/bin/env bash
set -euo pipefail

# Records the version semantic-release just published so the gated
# `publish-feed` job (protected `production-signing` environment) can sign and
# publish the appcast for exactly this release. The build job itself never
# touches the signing key.

VERSION="${1:-}"

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
