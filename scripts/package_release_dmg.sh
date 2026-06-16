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

cd "$ROOT_DIR"

xcodegen generate

rm -rf "$DIST_DIR" "$STAGING_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  build

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: expected app bundle at $APP_BUNDLE" >&2
  exit 1
fi

BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
  echo "error: expected CFBundleShortVersionString $VERSION, got $BUNDLE_VERSION" >&2
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

hdiutil verify "$DMG_PATH"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "Created $DMG_PATH"
echo "Created $CHECKSUM_PATH"
