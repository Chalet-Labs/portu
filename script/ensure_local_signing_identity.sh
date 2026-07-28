#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="Portu Local Development"
LOGIN_KEYCHAIN="$(
  security default-keychain -d user \
    | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
)"

has_identity() {
  security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null \
    | awk -v name="\"$IDENTITY_NAME\"" '
        index($0, name) { found = 1 }
        END { exit found ? 0 : 1 }
      '
}

if has_identity; then
  echo "$IDENTITY_NAME"
  exit 0
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/portu-signing.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

CERTIFICATE="$TEMP_DIR/certificate.pem"
PRIVATE_KEY="$TEMP_DIR/private-key.pem"
IDENTITY="$TEMP_DIR/identity.p12"
PASSPHRASE="$(uuidgen)"

echo "Creating the one-time '$IDENTITY_NAME' identity for stable Keychain access…" >&2

openssl req \
  -new \
  -newkey rsa:2048 \
  -x509 \
  -sha256 \
  -days 3650 \
  -nodes \
  -subj "/CN=$IDENTITY_NAME/O=Portu Local Development" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "$PRIVATE_KEY" \
  -out "$CERTIFICATE" \
  >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -name "$IDENTITY_NAME" \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -passout "pass:$PASSPHRASE" \
  -out "$IDENTITY"

security import "$IDENTITY" \
  -k "$LOGIN_KEYCHAIN" \
  -P "$PASSPHRASE" \
  -T /usr/bin/codesign \
  >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$LOGIN_KEYCHAIN" \
  "$CERTIFICATE"

if ! has_identity; then
  echo "Failed to create a valid '$IDENTITY_NAME' code-signing identity." >&2
  exit 1
fi

echo "$IDENTITY_NAME"
