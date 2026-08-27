#!/usr/bin/env bash
set -euo pipefail

VERSION=""
BUILD_NUMBER=""
DMG_PATH=""
DOWNLOAD_URL_PREFIX=""
RELEASE_NOTES_PATH=""
CHANNEL=""
ED_KEY_FILE=""
SIGN_FEED="NO"
UPDATES_BRANCH="updates"
REPO_URL=""
REMOTE_NAME="origin"
SKIP_REACHABILITY_CHECK="NO"
NO_PUSH="NO"

usage() {
  echo "usage: $0 --version <semver> --dmg <path> [--build-number <int>] [--download-url-prefix <url>] [--release-notes <path>] [--channel <name>] [--ed-key-file <file>] [--sign-feed] [--updates-branch <branch>] [--repo-url <url>] [--remote-name <name>] [--skip-reachability-check] [--no-push]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --dmg|--dmg-path)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --download-url-prefix)
      DOWNLOAD_URL_PREFIX="${2:-}"
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES_PATH="${2:-}"
      shift 2
      ;;
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --ed-key-file)
      ED_KEY_FILE="${2:-}"
      shift 2
      ;;
    --sign-feed)
      SIGN_FEED="YES"
      shift
      ;;
    --updates-branch)
      UPDATES_BRANCH="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --remote-name)
      REMOTE_NAME="${2:-}"
      shift 2
      ;;
    --skip-reachability-check|--no-reachability-check)
      SKIP_REACHABILITY_CHECK="YES"
      shift
      ;;
    --no-push)
      NO_PUSH="YES"
      shift
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

# 1. Validate version and DMG
if [[ -z "$VERSION" ]]; then
  echo "error: --version is required" >&2
  usage
  exit 2
fi

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$VERSION" =~ $SEMVER_REGEX ]]; then
  echo "error: version '$VERSION' is not a valid semantic version" >&2
  exit 2
fi

if [[ -z "$DMG_PATH" ]]; then
  echo "error: --dmg is required" >&2
  usage
  exit 2
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: DMG file not found at '$DMG_PATH'" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Infer build number if not passed
if [[ -z "$BUILD_NUMBER" ]]; then
  # Inspect CFBundleVersion from DMG first
  MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/portu-dmg-inspect.XXXXXX")"
  if hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet; then
    if [[ -f "$MOUNT_POINT/Portu.app/Contents/Info.plist" ]]; then
      BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$MOUNT_POINT/Portu.app/Contents/Info.plist" 2>/dev/null || true)"
    fi
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  fi
  rm -rf "$MOUNT_POINT"

  # If DMG inspection did not yield a build number, fall back to GITHUB_RUN_NUMBER
  if [[ -z "$BUILD_NUMBER" && -n "${GITHUB_RUN_NUMBER:-}" && "$GITHUB_RUN_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    BUILD_NUMBER="$GITHUB_RUN_NUMBER"
  fi
fi

if [[ -z "$BUILD_NUMBER" || ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: build number could not be determined and must be a positive integer" >&2
  exit 2
fi

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/Chalet-Labs/portu/releases/download/v$VERSION"
fi

if [[ ! "$DOWNLOAD_URL_PREFIX" =~ ^https://[^[:space:]]+$ ]]; then
  echo "error: download URL prefix must use HTTPS: '$DOWNLOAD_URL_PREFIX'" >&2
  exit 2
fi

if [[ -z "$CHANNEL" && "$VERSION" =~ -alpha ]]; then
  CHANNEL="alpha"
fi

# 2. Retrieve private Ed25519 seed safely
PRIVATE_SEED=""
if [[ -n "$ED_KEY_FILE" && "$ED_KEY_FILE" != "-" ]]; then
  if [[ ! -f "$ED_KEY_FILE" ]]; then
    echo "error: private key file '$ED_KEY_FILE' does not exist" >&2
    exit 2
  fi
  PRIVATE_SEED="$(<"$ED_KEY_FILE")"
elif [[ -n "${PORTU_SPARKLE_PRIVATE_KEY:-}" ]]; then
  PRIVATE_SEED="$PORTU_SPARKLE_PRIVATE_KEY"
elif [[ -n "${PORTU_SPARKLE_PRIVATE_SEED:-}" ]]; then
  PRIVATE_SEED="$PORTU_SPARKLE_PRIVATE_SEED"
elif [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  PRIVATE_SEED="$SPARKLE_PRIVATE_KEY"
elif [[ -n "${ED_KEY_FILE:-}" && "$ED_KEY_FILE" == "-" ]]; then
  if [[ -t 0 ]]; then
    echo "error: stdin is a TTY; private key must be piped when using '--ed-key-file -'" >&2
    exit 2
  fi
  PRIVATE_SEED="$(cat)"
elif [[ ! -t 0 ]]; then
  PRIVATE_SEED="$(cat)"
fi

PRIVATE_SEED="$(printf '%s' "$PRIVATE_SEED" | tr -d '[:space:]')"
if [[ -z "$PRIVATE_SEED" ]]; then
  echo "error: Sparkle private key / seed is missing" >&2
  exit 2
fi

trap 'unset PRIVATE_SEED' EXIT

if ! DECODED_LEN="$({ printf '%s' "$PRIVATE_SEED" | /usr/bin/base64 -D | /usr/bin/wc -c | /usr/bin/tr -d '[:space:]'; } 2>/dev/null)" || [[ "$DECODED_LEN" != "32" ]]; then
  echo "error: private seed must decode to a 32-byte Ed25519 seed" >&2
  exit 2
fi

# 3. Check public DMG reachability if not skipped
DMG_FILENAME="$(basename "$DMG_PATH")"
ENCLOSURE_URL="${DOWNLOAD_URL_PREFIX%/}/$DMG_FILENAME"

if [[ "$SKIP_REACHABILITY_CHECK" != "YES" ]]; then
  echo "Verifying public DMG enclosure reachability at $ENCLOSURE_URL..."
  if ! curl --fail -s -I -L --retry 5 --retry-delay 2 --connect-timeout 10 --max-time 60 -o /dev/null "$ENCLOSURE_URL"; then
    echo "error: release enclosure URL is unreachable: $ENCLOSURE_URL" >&2
    exit 1
  fi
  echo "Release enclosure verified reachable."
fi

# 4. Resolve repository URL for updates branch
if [[ -z "$REPO_URL" ]]; then
  REPO_URL="$(git config --get "remote.${REMOTE_NAME}.url" 2>/dev/null || true)"
  if [[ -z "$REPO_URL" ]]; then
    REPO_URL="$ROOT_DIR"
  fi
fi

# 5. Prepare isolated updates branch workspace
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/portu-publish-updates.XXXXXX")"
cleanup_workdir() {
  rm -rf "$WORK_DIR"
  unset PRIVATE_SEED
}
trap cleanup_workdir EXIT

# Clone or initialize the updates branch in isolation
HAS_REMOTE_BRANCH="NO"
if git ls-remote --exit-code --heads "$REPO_URL" "$UPDATES_BRANCH" >/dev/null 2>&1; then
  HAS_REMOTE_BRANCH="YES"
fi

if [[ "$HAS_REMOTE_BRANCH" == "YES" ]]; then
  git clone --single-branch -b "$UPDATES_BRANCH" "$REPO_URL" "$WORK_DIR" >/dev/null 2>&1
else
  # Initialize fresh orphan/updates branch in temporary repo
  git init -b "$UPDATES_BRANCH" "$WORK_DIR" >/dev/null 2>&1
  git -C "$WORK_DIR" remote add origin "$REPO_URL"
fi
# Configure token authentication for GitHub remotes if token is available
GIT_AUTH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -n "$GIT_AUTH_TOKEN" && "$REPO_URL" =~ github\.com ]]; then
  git -C "$WORK_DIR" config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GIT_AUTH_TOKEN" | base64)"
fi

git -C "$WORK_DIR" config commit.gpgsign false
git -C "$WORK_DIR" config user.name "${GIT_COMMITTER_NAME:-semantic-release-bot}"
git -C "$WORK_DIR" config user.email "${GIT_COMMITTER_EMAIL:-semantic-release-bot@users.noreply.github.com}"
APPCAST_TARGET="$WORK_DIR/appcast.xml"

# 6. Generate authenticated appcast entry into target appcast.xml
GENERATE_SCRIPT="$ROOT_DIR/scripts/generate_sparkle_appcast.sh"
if [[ ! -x "$GENERATE_SCRIPT" ]]; then
  echo "error: cannot execute $GENERATE_SCRIPT" >&2
  exit 1
fi

GEN_ARGS=(
  --version "$VERSION"
  --build-number "$BUILD_NUMBER"
  --dmg "$DMG_PATH"
  --appcast "$APPCAST_TARGET"
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
)

if [[ -n "$RELEASE_NOTES_PATH" && -f "$RELEASE_NOTES_PATH" ]]; then
  GEN_ARGS+=(--release-notes "$RELEASE_NOTES_PATH")
fi

if [[ -n "$CHANNEL" ]]; then
  GEN_ARGS+=(--channel "$CHANNEL")
fi

if [[ "$SIGN_FEED" == "YES" ]]; then
  GEN_ARGS+=(--sign-feed)
fi

printf '%s\n' "$PRIVATE_SEED" | "$GENERATE_SCRIPT" "${GEN_ARGS[@]}"

# 7. Check if appcast was modified (idempotency check)
cd "$WORK_DIR"
git add appcast.xml

if git diff --cached --quiet; then
  echo "Sparkle appcast on branch '$UPDATES_BRANCH' is already up to date for v$VERSION (idempotent)."
  exit 0
fi

# 8. Commit and push changes to updates branch
git commit --no-gpg-sign -m "chore(release): update Sparkle appcast for v${VERSION} [skip ci]"

if [[ "$NO_PUSH" != "YES" ]]; then
  if [[ "$HAS_REMOTE_BRANCH" == "YES" ]]; then
    # Push to existing branch with retry on potential concurrent update
    for attempt in 1 2 3; do
      if git push origin "$UPDATES_BRANCH" >/dev/null 2>&1; then
        echo "Successfully published updated Sparkle appcast to branch '$UPDATES_BRANCH' for v$VERSION"
        exit 0
      fi
      if [[ "$attempt" -eq 3 ]]; then
        echo "error: failed to push appcast update to branch '$UPDATES_BRANCH'" >&2
        exit 1
      fi
      if ! git pull --rebase origin "$UPDATES_BRANCH" >/dev/null 2>&1; then
        git rebase --abort >/dev/null 2>&1 || true
      fi
      printf '%s\n' "$PRIVATE_SEED" | "$GENERATE_SCRIPT" "${GEN_ARGS[@]}"
      git add appcast.xml
      if ! git diff --cached --quiet; then
        git commit --no-gpg-sign --amend --no-edit >/dev/null 2>&1 || git commit --no-gpg-sign -m "chore(release): update Sparkle appcast for v${VERSION} [skip ci]" >/dev/null 2>&1
      fi
    done
  else
    git push -u origin "$UPDATES_BRANCH" >/dev/null 2>&1 || {
      echo "error: failed to create and push to branch '$UPDATES_BRANCH'" >&2
      exit 1
    }
    echo "Successfully published updated Sparkle appcast to branch '$UPDATES_BRANCH' for v$VERSION"
  fi
else
  echo "Appcast generated and committed locally (--no-push active)."
fi
