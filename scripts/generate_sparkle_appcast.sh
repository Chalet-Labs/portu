#!/usr/bin/env bash
set -euo pipefail

VERSION=""
BUILD_NUMBER=""
DMG_PATH=""
APPCAST_PATH=""
DOWNLOAD_URL_PREFIX=""
RELEASE_NOTES_PATH=""
CHANNEL=""
LINK="https://github.com/Chalet-Labs/portu"
ED_KEY_FILE=""
SIGN_FEED="NO"
EXPECTED_PUBLIC_KEY=""

usage() {
  echo "usage: $0 --version <semver> --build-number <int> --dmg <path> --appcast <path> --download-url-prefix <url> [--release-notes <path>] [--channel <name>] [--link <url>] [--ed-key-file <file>] [--expected-public-key <base64>] [--sign-feed]" >&2
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
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --appcast)
      APPCAST_PATH="${2:-}"
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
    --link)
      LINK="${2:-}"
      shift 2
      ;;
    --ed-key-file)
      ED_KEY_FILE="${2:-}"
      shift 2
      ;;
    --expected-public-key)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --expected-public-key requires a value" >&2
        usage
        exit 2
      fi
      EXPECTED_PUBLIC_KEY="$2"
      shift 2
      ;;
    --sign-feed)
      SIGN_FEED="YES"
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

# 1. Validate required fields
if [[ -z "$VERSION" ]]; then
  echo "error: version is required" >&2
  exit 2
fi

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$VERSION" =~ $SEMVER_REGEX ]]; then
  echo "error: '$VERSION' is not a valid semantic version" >&2
  exit 2
fi

if [[ -z "$BUILD_NUMBER" || ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: build number must be a positive integer" >&2
  exit 2
fi

if [[ -z "$DMG_PATH" ]]; then
  echo "error: DMG path is required" >&2
  exit 2
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: DMG file does not exist: $DMG_PATH" >&2
  exit 2
fi

if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  if [[ ! -f "$RELEASE_NOTES_PATH" ]]; then
    echo "error: release notes file does not exist: $RELEASE_NOTES_PATH" >&2
    exit 2
  fi
fi

if [[ -z "$APPCAST_PATH" ]]; then
  echo "error: appcast output path is required" >&2
  exit 2
fi

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  echo "error: download URL prefix is required" >&2
  exit 2
fi

if [[ ! "$DOWNLOAD_URL_PREFIX" =~ ^https://[^[:space:]]+$ ]]; then
  echo "error: download URL prefix must use HTTPS: $DOWNLOAD_URL_PREFIX" >&2
  exit 2
fi

# Automatically infer alpha channel if not explicitly provided
if [[ -z "$CHANNEL" && "$VERSION" =~ -alpha ]]; then
  CHANNEL="alpha"
fi

# 2. Retrieve and validate private Ed25519 seed
PRIVATE_SEED=""
if [[ -n "$ED_KEY_FILE" && "$ED_KEY_FILE" != "-" ]]; then
  if [[ ! -f "$ED_KEY_FILE" ]]; then
    echo "error: private key file does not exist: $ED_KEY_FILE" >&2
    exit 2
  fi
  PRIVATE_SEED="$(cat "$ED_KEY_FILE")"
else
  # Read from stdin
  if [ -t 0 ]; then
    echo "error: private key seed is required on stdin or via --ed-key-file" >&2
    exit 2
  fi
  PRIVATE_SEED="$(cat)"
fi

PRIVATE_SEED="$(printf '%s' "$PRIVATE_SEED" | tr -d '[:space:]')"
if [[ -z "$PRIVATE_SEED" ]]; then
  echo "error: private key seed cannot be empty" >&2
  exit 2
fi

trap 'unset PRIVATE_SEED' EXIT

if ! DECODED_LEN="$({ printf '%s' "$PRIVATE_SEED" | /usr/bin/base64 -D | /usr/bin/wc -c | /usr/bin/tr -d '[:space:]'; } 2>/dev/null)" || [[ "$DECODED_LEN" != "32" ]]; then
  echo "error: private key seed must be valid base64 for a 32-byte Ed25519 key" >&2
  exit 2
fi

# Fail closed when an expected public key is supplied but malformed.
if [[ -n "$EXPECTED_PUBLIC_KEY" ]]; then
  if ! EXPECTED_DECODED_LEN="$({ printf '%s' "$EXPECTED_PUBLIC_KEY" | /usr/bin/base64 -D | /usr/bin/wc -c | /usr/bin/tr -d '[:space:]'; } 2>/dev/null)" || [[ "$EXPECTED_DECODED_LEN" != "32" ]]; then
    echo "error: expected public key must be a base64-encoded 32-byte Ed25519 key" >&2
    exit 2
  fi
fi

# 3. Locate Sparkle official tools
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATE_APPCAST=""
SIGN_UPDATE=""

find_sparkle_tool() {
  local tool_name="$1"
  local candidate
  for candidate in \
    "$ROOT_DIR/.build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name" \
    "$ROOT_DIR/.build/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name" \
    "$ROOT_DIR/.build/SourcePackages/checkouts/Sparkle/$tool_name" \
    ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/"$tool_name"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  if command -v "$tool_name" >/dev/null 2>&1; then
    command -v "$tool_name"
    return 0
  fi
  return 1
}

GENERATE_APPCAST="$(find_sparkle_tool generate_appcast || true)"
SIGN_UPDATE="$(find_sparkle_tool sign_update || true)"

if [[ -z "$GENERATE_APPCAST" || ! -x "$GENERATE_APPCAST" || -z "$SIGN_UPDATE" || ! -x "$SIGN_UPDATE" ]]; then
  echo "error: Sparkle tools (generate_appcast, sign_update) not found" >&2
  exit 1
fi

# 4. Prepare isolated staging directory
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/portu-appcast-stage.XXXXXX")"
cleanup_stage() {
  rm -rf "$STAGE_DIR"
}
trap 'cleanup_stage; unset PRIVATE_SEED' EXIT

DMG_FILENAME="$(basename "$DMG_PATH")"
DMG_STEM="${DMG_FILENAME%.dmg}"
cp "$DMG_PATH" "$STAGE_DIR/$DMG_FILENAME"

# Stage release notes if provided
if [[ -n "$RELEASE_NOTES_PATH" && -f "$RELEASE_NOTES_PATH" ]]; then
  cp "$RELEASE_NOTES_PATH" "$STAGE_DIR/$DMG_STEM.md"
fi

# Preserve prior appcast items if output appcast already exists
if [[ -f "$APPCAST_PATH" ]]; then
  cp "$APPCAST_PATH" "$STAGE_DIR/appcast.xml"
fi

# Ensure URL prefix has trailing slash for generate_appcast
DOWNLOAD_PREFIX_FORMATTED="${DOWNLOAD_URL_PREFIX%/}/"

# 5. Run Sparkle generate_appcast
GEN_ARGS=(
  --ed-key-file -
  --download-url-prefix "$DOWNLOAD_PREFIX_FORMATTED"
  --maximum-versions 0
  --maximum-deltas 0
  --embed-release-notes
  --link "$LINK"
  -o "$STAGE_DIR/appcast.xml"
)

if [[ -n "$CHANNEL" ]]; then
  GEN_ARGS+=(--channel "$CHANNEL")
fi

GEN_ARGS+=("$STAGE_DIR")

printf '%s\n' "$PRIVATE_SEED" | "$GENERATE_APPCAST" "${GEN_ARGS[@]}"

if [[ ! -f "$STAGE_DIR/appcast.xml" ]]; then
  echo "error: generate_appcast failed to produce appcast.xml" >&2
  exit 1
fi

# 6. Validate generated item's version and build number against CLI inputs
BUNDLE_MARKETING_VERSION="${VERSION%%[-+]*}"
if ! grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$STAGE_DIR/appcast.xml"; then
  echo "error: generated appcast does not match expected build number $BUILD_NUMBER" >&2
  exit 1
fi

if ! grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$STAGE_DIR/appcast.xml" && \
   ! grep -q "<sparkle:shortVersionString>$BUNDLE_MARKETING_VERSION</sparkle:shortVersionString>" "$STAGE_DIR/appcast.xml"; then
  echo "error: generated appcast does not match expected short version $VERSION" >&2
  exit 1
fi

# 7. Verify enclosure signature, URL, and byte length in generated appcast
EXPECTED_URL="${DOWNLOAD_URL_PREFIX%/}/$DMG_FILENAME"
EXPECTED_LENGTH="$(stat -f '%z' "$DMG_PATH")"

if ! grep -q "$EXPECTED_URL" "$STAGE_DIR/appcast.xml"; then
  echo "error: generated appcast does not contain expected enclosure URL: $EXPECTED_URL" >&2
  exit 1
fi

if ! grep -q "length=\"$EXPECTED_LENGTH\"" "$STAGE_DIR/appcast.xml"; then
  echo "error: generated appcast does not contain expected archive length: $EXPECTED_LENGTH" >&2
  exit 1
fi

if [[ -n "$CHANNEL" ]]; then
  if ! grep -q "<sparkle:channel>$CHANNEL</sparkle:channel>" "$STAGE_DIR/appcast.xml"; then
    echo "error: generated appcast missing channel tag for $CHANNEL" >&2
    exit 1
  fi
fi

# Extract the actual enclosure signature generated in appcast.xml using xmllint
ENCLOSURE_SIGNATURE="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$STAGE_DIR/appcast.xml" 2>/dev/null || true)"

if [[ -z "$ENCLOSURE_SIGNATURE" ]]; then
  echo "error: generated appcast does not contain a valid enclosure Ed25519 signature" >&2
  exit 1
fi

# Verify the extracted enclosure signature directly with sign_update --verify
if ! printf '%s\n' "$PRIVATE_SEED" | "$SIGN_UPDATE" --verify --ed-key-file - "$DMG_PATH" "$ENCLOSURE_SIGNATURE" >/dev/null 2>&1; then
  echo "error: generated Ed25519 enclosure signature failed verification against DMG" >&2
  exit 1
fi

# Verify the archive signature against the expected PUBLIC key so a feed can
# only be generated when clients' embedded trust anchor accepts it.
if [[ -n "$EXPECTED_PUBLIC_KEY" ]]; then
  if ! "$ROOT_DIR/scripts/verify_sparkle_signature.swift" "$EXPECTED_PUBLIC_KEY" "$DMG_PATH" "$ENCLOSURE_SIGNATURE"; then
    echo "error: generated archive signature does not verify against the expected public key" >&2
    exit 1
  fi
fi

# 8. Optionally sign feed if --sign-feed was specified
if [[ "$SIGN_FEED" == "YES" ]]; then
  printf '%s\n' "$PRIVATE_SEED" | "$SIGN_UPDATE" --ed-key-file - "$STAGE_DIR/appcast.xml"
  if ! printf '%s\n' "$PRIVATE_SEED" | "$SIGN_UPDATE" --verify --ed-key-file - "$STAGE_DIR/appcast.xml" >/dev/null 2>&1; then
    echo "error: signed feed signature failed verification" >&2
    exit 1
  fi
fi

# 9. Write to destination appcast path
mkdir -p "$(dirname "$APPCAST_PATH")"
cp "$STAGE_DIR/appcast.xml" "$APPCAST_PATH"

echo "Generated authenticated Sparkle appcast at $APPCAST_PATH"
