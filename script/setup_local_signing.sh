#!/usr/bin/env bash
# Writes Configs/Local.xcconfig so Debug builds from this checkout sign with an Apple Development identity.
#
# Ad hoc and self-signed builds have no Apple team ID, so the keychain records each build's cdhash
# and asks for access again after every rebuild. An Apple Development identity carries a team ID,
# and "Always Allow" then holds across rebuilds. A free Apple ID in Xcode is enough.
#
# No provisioning profile is used: one would add an application-identifier entitlement and move
# the app to the data protection keychain, where the existing items do not live.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/Configs/Local.xcconfig"
TEAM=""

usage() {
  echo "usage: $0 [--team TEAM_ID] [--output PATH]" >&2
  exit 64
}

while [ $# -gt 0 ]; do
  case "$1" in
    --output) [ $# -ge 2 ] || usage; OUTPUT="$2"; shift 2 ;;
    --team) [ $# -ge 2 ] || usage; TEAM="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [ -n "$TEAM" ] && ! [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "A team ID is 10 uppercase letters and digits, got: $TEAM" >&2
  usage
fi

team_of() {
  security find-certificate -c "$1" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10})([,/].*)?$/\1/p'
}

teams=()
while IFS= read -r name; do
  team="$(team_of "$name" || true)"
  if [ -n "$team" ]; then
    teams+=("$team")
  fi
done < <(
  security find-identity -v -p codesigning \
    | sed -nE 's/^ *[0-9]+\) [0-9A-F]{40} "(Apple Development: .*)"$/\1/p'
)

if [ ${#teams[@]} -eq 0 ]; then
  cat >&2 <<'MESSAGE'
No valid Apple Development identity found.

In Xcode, open Settings > Accounts, add your Apple ID (a free account is enough),
select the Personal Team, choose Manage Certificates, and add an Apple Development
certificate. Then run `just signing-setup` again.
MESSAGE
  exit 1
fi

unique_teams=$(printf '%s\n' "${teams[@]}" | sort -u)

if [ -z "$TEAM" ]; then
  if [ "$(printf '%s\n' "$unique_teams" | wc -l | tr -d ' ')" -ne 1 ]; then
    echo "Apple Development identities exist for several teams:" >&2
    printf '%s\n' "$unique_teams" | sed 's/^/  /' >&2
    echo "Choose one with --team TEAM_ID." >&2
    exit 2
  fi
  TEAM="$unique_teams"
elif ! printf '%s\n' "$unique_teams" | grep -qxF -- "$TEAM"; then
  echo "No Apple Development identity for team $TEAM. Available: ${unique_teams//$'\n'/ }" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<CONFIG
// Written by script/setup_local_signing.sh for this checkout only (ignored by git).
// Debug builds sign with the Apple Development identity of team $TEAM, without a provisioning profile.
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = $TEAM
PROVISIONING_PROFILE_SPECIFIER =
CONFIG

echo "Wrote $OUTPUT for team $TEAM."
