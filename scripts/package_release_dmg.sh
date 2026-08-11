#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Portu"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <semantic-version>" >&2
  exit 2
fi

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$VERSION" =~ $SEMVER_REGEX ]]; then
  echo "error: '$VERSION' is not a semantic version" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
PROJECT="$ROOT_DIR/Portu.xcodeproj"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DERIVED_DATA/ReleaseStaging"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-0}"
BUNDLE_MARKETING_VERSION="${VERSION%%[-+]*}"
PROOF_MODE="${PORTU_SPARKLE_PROOF:-NO}"
PROOF_FEED_URL="${PORTU_UPDATE_FEED_URL:-}"
PROOF_PUBLIC_KEY="${PORTU_UPDATE_PUBLIC_KEY:-}"
UPDATE_BUILD_SETTINGS=()

mounted_devices_for_image() {
  hdiutil info -plist | /usr/bin/python3 -c '
import os
import plistlib
import sys

target = os.path.realpath(sys.argv[1])
info = plistlib.load(sys.stdin.buffer)
for image in info.get("images", []):
    if os.path.realpath(image.get("image-path", "")) == target:
        entities = image.get("system-entities", [])
        if entities and entities[0].get("dev-entry"):
            print(entities[0]["dev-entry"])
' "$1"
}

verify_dmg() {
  local dmg_path="$1"
  local attempt
  local mounted_device

  for attempt in 1 2 3; do
    if hdiutil verify "$dmg_path"; then
      return 0
    fi

    while IFS= read -r mounted_device; do
      [[ -z "$mounted_device" ]] || hdiutil detach "$mounted_device" || true
    done < <(mounted_devices_for_image "$dmg_path")

    if (( attempt < 3 )); then
      sleep "$attempt"
    fi
  done

  return 1
}

if [[ "$PROOF_MODE" == "YES" || -n "$PROOF_FEED_URL" || -n "$PROOF_PUBLIC_KEY" ]]; then
  if [[ "$PROOF_MODE" != "YES" ]]; then
    echo "error: proof updater overrides require PORTU_SPARKLE_PROOF=YES" >&2
    exit 2
  fi
  if [[ -z "$PROOF_FEED_URL" || -z "$PROOF_PUBLIC_KEY" ]]; then
    echo "error: proof updater overrides require both feed URL and public key" >&2
    exit 2
  fi

  "$ROOT_DIR/scripts/validate_sparkle_proof_configuration.sh" "$PROOF_FEED_URL" "$PROOF_PUBLIC_KEY"
  UPDATE_BUILD_SETTINGS+=(
    PORTU_UPDATE_FEED_URL="$PROOF_FEED_URL"
    PORTU_UPDATE_PUBLIC_KEY="$PROOF_PUBLIC_KEY"
    PORTU_VERIFY_UPDATE_BEFORE_EXTRACTION=YES
  )
fi

cd "$ROOT_DIR"

xcodegen generate

rm -rf "$DIST_DIR" "$STAGING_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -packageAuthorizationProvider netrc \
  -skipMacroValidation \
  MARKETING_VERSION="$BUNDLE_MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  "${UPDATE_BUILD_SETTINGS[@]}" \
  build

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: expected app bundle at $APP_BUNDLE" >&2
  exit 1
fi

BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$BUNDLE_MARKETING_VERSION" ]]; then
  echo "error: expected CFBundleShortVersionString $BUNDLE_MARKETING_VERSION, got $BUNDLE_VERSION" >&2
  exit 1
fi

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

verify_dmg "$DMG_PATH"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "Created $DMG_PATH"
echo "Created $CHECKSUM_PATH"
