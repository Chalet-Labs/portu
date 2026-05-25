#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-}"

if [[ -z "$TAG" ]]; then
  echo "usage: $0 <git-tag>" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: GitHub CLI is required to mark releases as pre-release" >&2
  exit 1
fi

if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  gh release edit "$TAG" --prerelease --repo "$GITHUB_REPOSITORY"
  is_prerelease="$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json isPrerelease --jq '.isPrerelease')"
else
  gh release edit "$TAG" --prerelease
  is_prerelease="$(gh release view "$TAG" --json isPrerelease --jq '.isPrerelease')"
fi

if [[ "$is_prerelease" != "true" ]]; then
  echo "error: $TAG did not get the prerelease flag" >&2
  exit 1
fi

echo "Marked $TAG as a GitHub pre-release"
