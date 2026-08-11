#!/usr/bin/env bash
set -euo pipefail

BASE_URL=""
N_VERSION=""
N_BUILD=""
NEXT_VERSION=""
NEXT_BUILD=""
OUTPUT_DIR=""
PLAN_ONLY="NO"

usage() {
  echo "usage: $0 --base-url <https-url> --n-version <version> --n-build <build> --next-version <version> --next-build <build> --output <directory> [--plan-only]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --n-version)
      N_VERSION="${2:-}"
      shift 2
      ;;
    --n-build)
      N_BUILD="${2:-}"
      shift 2
      ;;
    --next-version)
      NEXT_VERSION="${2:-}"
      shift 2
      ;;
    --next-build)
      NEXT_BUILD="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --plan-only)
      PLAN_ONLY="YES"
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

BASE_URL="${BASE_URL%/}"
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

if [[ ! "$BASE_URL" =~ ^https://localhost:([0-9]+)$ ]]; then
  echo "error: proof base URL must use HTTPS localhost with an explicit port" >&2
  exit 2
fi
PROOF_PORT="${BASE_URL##*:}"
if (( PROOF_PORT < 1 || PROOF_PORT > 65535 )); then
  echo "error: proof HTTPS port must be between 1 and 65535" >&2
  exit 2
fi
if [[ ! "$N_VERSION" =~ $SEMVER_REGEX || ! "$NEXT_VERSION" =~ $SEMVER_REGEX ]]; then
  echo "error: proof versions must use semantic versioning" >&2
  exit 2
fi
if [[ ! "$N_BUILD" =~ ^[0-9]+$ || ! "$NEXT_BUILD" =~ ^[0-9]+$ ]]; then
  echo "error: proof build numbers must be positive integers" >&2
  exit 2
fi
if (( NEXT_BUILD <= N_BUILD )); then
  echo "error: N+1 build number must be greater than N build number" >&2
  exit 2
fi
if [[ -z "$OUTPUT_DIR" ]]; then
  echo "error: proof output directory is required" >&2
  exit 2
fi

echo "proof_feed_url=$BASE_URL/appcast.xml"
echo "n=$N_VERSION+$N_BUILD"
echo "next=$NEXT_VERSION+$NEXT_BUILD"
echo "output=$OUTPUT_DIR"

if [[ "$PLAN_ONLY" == "YES" ]]; then
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$OUTPUT_DIR")"

if [[ "$OUTPUT_DIR" != "$ROOT_DIR/.build/"* ]]; then
  echo "error: proof output must be inside $ROOT_DIR/.build" >&2
  exit 2
fi
if [[ -d "$OUTPUT_DIR" ]]; then
  if [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "error: proof output directory must not already contain files: $OUTPUT_DIR" >&2
    exit 2
  fi
fi

RELEASES_DIR="$OUTPUT_DIR/releases"
SERVER_DIR="$OUTPUT_DIR/server"
NEGATIVE_DIR="$OUTPUT_DIR/negative"
TLS_DIR="$OUTPUT_DIR/tls"
mkdir -p "$RELEASES_DIR" "$SERVER_DIR" "$NEGATIVE_DIR" "$TLS_DIR"

PRIVATE_SEED="$(openssl rand -base64 32 | tr -d '\n')"
trap 'unset PRIVATE_SEED' EXIT
PUBLIC_KEY="$(printf '%s\n' "$PRIVATE_SEED" | "$ROOT_DIR/scripts/derive_sparkle_public_key.swift")"
"$ROOT_DIR/scripts/validate_sparkle_proof_configuration.sh" "$BASE_URL/appcast.xml" "$PUBLIC_KEY"

build_release() {
  local version="$1"
  local build_number="$2"
  local destination="$3"

  echo "Building Portu $version ($build_number) with credential-free ad-hoc signing…"
  GITHUB_RUN_NUMBER="$build_number" \
    PORTU_SPARKLE_PROOF=YES \
    PORTU_UPDATE_FEED_URL="$BASE_URL/appcast.xml" \
    PORTU_UPDATE_PUBLIC_KEY="$PUBLIC_KEY" \
    "$ROOT_DIR/scripts/package_release_dmg.sh" "$version"

  cp "$ROOT_DIR/dist/Portu-$version.dmg" "$destination/"
  cp "$ROOT_DIR/dist/Portu-$version.dmg.sha256" "$destination/"
}

verify_release_dmg() (
  local dmg_path="$1"
  local expected_version="$2"
  local expected_build="$3"
  local mount_dir
  local app_path
  local actual_version
  local actual_build
  local actual_feed
  local actual_key
  local verify_before_extraction
  local architectures
  local signature_metadata

  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/portu-proof-mount.XXXXXX")"
  cleanup_mounted_release() {
    hdiutil detach -quiet "$mount_dir" >/dev/null 2>&1 || true
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  }
  trap cleanup_mounted_release EXIT

  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_dir" "$dmg_path"
  app_path="$mount_dir/Portu.app"

  if [[ ! -d "$app_path" ]]; then
    echo "error: $dmg_path does not contain Portu.app" >&2
    exit 1
  fi

  codesign --verify --deep --strict "$app_path"
  signature_metadata="$(codesign -d --verbose=4 "$app_path" 2>&1)"
  if ! grep -q '^Signature=adhoc$' <<< "$signature_metadata"; then
    echo "error: $dmg_path is not ad-hoc signed" >&2
    exit 1
  fi

  actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
  actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
  actual_feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app_path/Contents/Info.plist")"
  actual_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app_path/Contents/Info.plist")"
  verify_before_extraction="$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$app_path/Contents/Info.plist")"
  architectures="$(lipo -archs "$app_path/Contents/MacOS/Portu")"

  if [[ "$actual_version" != "$expected_version" || "$actual_build" != "$expected_build" ]]; then
    echo "error: $dmg_path contains unexpected version $actual_version ($actual_build)" >&2
    exit 1
  fi
  if [[ "$actual_feed" != "$BASE_URL/appcast.xml" || "$actual_key" != "$PUBLIC_KEY" ]]; then
    echo "error: $dmg_path does not embed the proof feed and disposable public key" >&2
    exit 1
  fi
  if [[ "$verify_before_extraction" != "YES" ]]; then
    echo "error: $dmg_path does not require archive verification before extraction" >&2
    exit 1
  fi
  if [[ "$architectures" != *"arm64"* || "$architectures" != *"x86_64"* ]]; then
    echo "error: $dmg_path is not a universal release artifact" >&2
    exit 1
  fi
)

build_release "$N_VERSION" "$N_BUILD" "$RELEASES_DIR"
build_release "$NEXT_VERSION" "$NEXT_BUILD" "$SERVER_DIR"

N_DMG="$RELEASES_DIR/Portu-$N_VERSION.dmg"
NEXT_DMG="$SERVER_DIR/Portu-$NEXT_VERSION.dmg"
verify_release_dmg "$N_DMG" "$N_VERSION" "$N_BUILD"
verify_release_dmg "$NEXT_DMG" "$NEXT_VERSION" "$NEXT_BUILD"

GENERATE_APPCAST="$(find "$ROOT_DIR/.build/DerivedData/SourcePackages/artifacts" -path '*/Sparkle/bin/generate_appcast' -type f -print -quit)"
SIGN_UPDATE="$(find "$ROOT_DIR/.build/DerivedData/SourcePackages/artifacts" -path '*/Sparkle/bin/sign_update' -type f -print -quit)"
if [[ ! -x "$GENERATE_APPCAST" || ! -x "$SIGN_UPDATE" ]]; then
  echo "error: Sparkle proof tools were not resolved by the release builds" >&2
  exit 1
fi

cat > "$SERVER_DIR/Portu-$NEXT_VERSION.md" <<EOF
# Portu updater proof $NEXT_VERSION

Disposable issue #79 artifact for authenticated ad-hoc update verification.
EOF

printf '%s\n' "$PRIVATE_SEED" | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "$BASE_URL/" \
  --link "https://github.com/Chalet-Labs/portu" \
  --versions "$NEXT_BUILD" \
  --maximum-versions 0 \
  --maximum-deltas 0 \
  -o "$SERVER_DIR/appcast.xml" \
  "$SERVER_DIR"

ARCHIVE_SIGNATURE="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$SERVER_DIR/appcast.xml")"
ARCHIVE_LENGTH="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@length)' "$SERVER_DIR/appcast.xml")"
ARCHIVE_URL="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$SERVER_DIR/appcast.xml")"
EXPECTED_LENGTH="$(stat -f '%z' "$NEXT_DMG")"
EXPECTED_URL="$BASE_URL/$(basename "$NEXT_DMG")"

if [[ -z "$ARCHIVE_SIGNATURE" || "$ARCHIVE_LENGTH" != "$EXPECTED_LENGTH" || "$ARCHIVE_URL" != "$EXPECTED_URL" ]]; then
  echo "error: generated appcast enclosure does not match the N+1 DMG" >&2
  exit 1
fi
printf '%s\n' "$PRIVATE_SEED" | "$SIGN_UPDATE" \
  --verify \
  --ed-key-file - \
  "$NEXT_DMG" \
  "$ARCHIVE_SIGNATURE"

TAMPERED_DMG="$NEGATIVE_DIR/Portu-$NEXT_VERSION-tampered.dmg"
cp "$NEXT_DMG" "$TAMPERED_DMG"
printf 'X' >> "$TAMPERED_DMG"
TAMPERED_LENGTH="$(stat -f '%z' "$TAMPERED_DMG")"
if printf '%s\n' "$PRIVATE_SEED" | "$SIGN_UPDATE" \
  --verify \
  --ed-key-file - \
  "$TAMPERED_DMG" \
  "$ARCHIVE_SIGNATURE" >/dev/null 2>&1; then
  echo "error: tampered N+1 DMG unexpectedly passed signature verification" >&2
  exit 1
fi

EXPECTED_TAMPERED_URL="$BASE_URL/$(basename "$TAMPERED_DMG")"
sed \
  -e "s|$EXPECTED_URL|$EXPECTED_TAMPERED_URL|" \
  -e "s|length=\"$ARCHIVE_LENGTH\"|length=\"$TAMPERED_LENGTH\"|" \
  "$SERVER_DIR/appcast.xml" > "$SERVER_DIR/tampered-appcast.xml"
sed "s|$EXPECTED_URL|$BASE_URL/missing-Portu-$NEXT_VERSION.dmg|" \
  "$SERVER_DIR/appcast.xml" > "$SERVER_DIR/missing-enclosure-appcast.xml"
cp "$TAMPERED_DMG" "$SERVER_DIR/"

TAMPERED_APPCAST_URL="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$SERVER_DIR/tampered-appcast.xml")"
TAMPERED_APPCAST_LENGTH="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@length)' "$SERVER_DIR/tampered-appcast.xml")"
if [[ "$TAMPERED_APPCAST_URL" != "$EXPECTED_TAMPERED_URL" || "$TAMPERED_APPCAST_LENGTH" != "$TAMPERED_LENGTH" ]]; then
  echo "error: tampered appcast must retain the original signature with the tampered archive URL and length" >&2
  exit 1
fi

openssl req -x509 -newkey rsa:2048 -sha256 -days 2 -nodes \
  -subj '/CN=Portu Updater Proof CA' \
  -keyout "$TLS_DIR/ca-key.pem" \
  -out "$TLS_DIR/ca-cert.pem" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes \
  -subj '/CN=localhost' \
  -keyout "$TLS_DIR/server-key.pem" \
  -out "$TLS_DIR/server.csr" >/dev/null 2>&1
cat > "$TLS_DIR/server.ext" <<'EOF'
subjectAltName=DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
EOF
openssl x509 -req -sha256 -days 2 \
  -in "$TLS_DIR/server.csr" \
  -CA "$TLS_DIR/ca-cert.pem" \
  -CAkey "$TLS_DIR/ca-key.pem" \
  -CAcreateserial \
  -extfile "$TLS_DIR/server.ext" \
  -out "$TLS_DIR/server-cert.pem" >/dev/null 2>&1
rm -f "$TLS_DIR/ca-key.pem" "$TLS_DIR/ca-cert.srl" "$TLS_DIR/server.csr" "$TLS_DIR/server.ext"
chmod 600 "$TLS_DIR/server-key.pem"

N_SHA256="$(shasum -a 256 "$N_DMG" | awk '{print $1}')"
NEXT_SHA256="$(shasum -a 256 "$NEXT_DMG" | awk '{print $1}')"
TAMPERED_SHA256="$(shasum -a 256 "$TAMPERED_DMG" | awk '{print $1}')"
APPCAST_SHA256="$(shasum -a 256 "$SERVER_DIR/appcast.xml" | awk '{print $1}')"

python3 - "$OUTPUT_DIR/manifest.json" <<EOF
import json
import sys

manifest = {
    "feed_url": "$BASE_URL/appcast.xml",
    "public_key": "$PUBLIC_KEY",
    "private_key_persisted": False,
    "apple_signing": "adhoc",
    "verify_before_extraction": True,
    "n": {
        "version": "$N_VERSION",
        "build": "$N_BUILD",
        "dmg": "releases/$(basename "$N_DMG")",
        "sha256": "$N_SHA256",
    },
    "next": {
        "version": "$NEXT_VERSION",
        "build": "$NEXT_BUILD",
        "dmg": "server/$(basename "$NEXT_DMG")",
        "sha256": "$NEXT_SHA256",
        "archive_signature": "$ARCHIVE_SIGNATURE",
        "archive_length": int("$ARCHIVE_LENGTH"),
    },
    "appcast_sha256": "$APPCAST_SHA256",
    "tampered": {
        "dmg": "negative/$(basename "$TAMPERED_DMG")",
        "sha256": "$TAMPERED_SHA256",
        "archive_length": int("$TAMPERED_LENGTH"),
        "retained_archive_signature": "$ARCHIVE_SIGNATURE",
        "signature_verification": "rejected",
    },
    "manual_results": {
        "clean_user": None,
        "installed_in_applications": None,
        "no_download_before_approval": None,
        "explicit_install_approval": None,
        "relaunched_as_next": None,
        "duplicate_processes": None,
        "portfolio_data_preserved": None,
        "settings_preserved": None,
        "keychain_credentials_preserved": None,
        "tampered_update_rejected": None,
        "unavailable_feed_recoverable": None,
        "missing_enclosure_recoverable": None,
    },
}

with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(manifest, output, indent=2, sort_keys=True)
    output.write("\n")
EOF

if ! printf '%s\n' "$PRIVATE_SEED" | python3 -c '
import pathlib
import sys

seed = sys.stdin.buffer.readline().rstrip(b"\n")
root = pathlib.Path(sys.argv[1])
for path in root.rglob("*"):
    if path.is_file() and seed in path.read_bytes():
        sys.exit(1)
' "$OUTPUT_DIR"; then
  echo "error: disposable private key leaked into proof artifacts" >&2
  exit 1
fi

echo "Prepared proof artifacts in $OUTPUT_DIR"
echo "Public key: $PUBLIC_KEY"
echo "Start the feed with: scripts/serve_sparkle_adhoc_proof.py --directory '$SERVER_DIR' --cert '$TLS_DIR/server-cert.pem' --key '$TLS_DIR/server-key.pem' --port '$PROOF_PORT'"
