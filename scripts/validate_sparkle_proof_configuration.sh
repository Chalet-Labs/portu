#!/usr/bin/env bash
set -euo pipefail

FEED_URL="${1:-}"
PUBLIC_KEY="${2:-}"

if [[ ! "$FEED_URL" =~ ^https://[^[:space:]]+$ ]]; then
  echo "error: proof update feed must use HTTPS" >&2
  exit 2
fi

if ! DECODED_LENGTH="$({ printf '%s' "$PUBLIC_KEY" | /usr/bin/base64 -D | /usr/bin/wc -c | /usr/bin/tr -d '[:space:]'; } 2>/dev/null)"; then
  echo "error: proof update public key must be valid base64 for a 32-byte Ed25519 key" >&2
  exit 2
fi

if [[ "$DECODED_LENGTH" != "32" ]]; then
  echo "error: proof update public key must be valid base64 for a 32-byte Ed25519 key" >&2
  exit 2
fi
