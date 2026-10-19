#!/usr/bin/env bash
# Prints the test groups that changed paths can affect, one per line, sorted.
# The rules live in script/test-scope.json: every rule whose glob matches a path adds its groups,
# and a path that no rule matches selects every group. `just test-affected` and PR CI read this.
#
# Usage:
#   script/test_scope.sh --base <ref>     <ref>...HEAD plus staged, unstaged and untracked files
#   script/test_scope.sh --paths-from -   newline-separated paths on stdin
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rules_file="$script_dir/test-scope.json"
all_groups="core network ui app release"

usage() {
  echo "usage: script/test_scope.sh --base <ref> | --paths-from -" >&2
  exit 2
}

# --no-renames lists both sides of a move, so a file moved out of a package still selects it.
changed_paths() {
  local repo_root
  repo_root="$(cd "$script_dir/.." && pwd)"
  git -C "$repo_root" diff --name-only --no-renames "$1...HEAD" &&
    git -C "$repo_root" diff --name-only --no-renames --cached &&
    git -C "$repo_root" diff --name-only --no-renames &&
    git -C "$repo_root" ls-files --others --exclude-standard
}

case "${1:-}" in
  --base)
    [[ $# -eq 2 && -n ${2:-} ]] || usage
    base="$2"
    ;;
  --paths-from)
    [[ $# -eq 2 && ${2:-} == - ]] || usage
    base=""
    ;;
  *) usage ;;
esac

command -v jq >/dev/null || { echo "test_scope.sh: jq is required" >&2; exit 1; }

rules="$(jq -r '.[] | [.glob, (.groups | join(" "))] | @tsv' "$rules_file")"
if [[ -n $base ]]; then
  paths="$(changed_paths "$base")"
else
  paths="$(cat)"
fi

selected=""
while IFS= read -r path; do
  if [[ -z $path ]]; then continue; fi
  matched=0
  while IFS=$'\t' read -r glob groups; do
    # Unquoted on purpose: $glob is a pattern, and * also matches /.
    if [[ $path == $glob ]]; then
      matched=1
      selected+=" $groups"
    fi
  done <<<"$rules"
  if [[ $matched -eq 0 ]]; then selected+=" all"; fi
done <<<"$paths"

# A function, because bash 3.2 can't parse a case statement inside $( ).
expand_groups() {
  local group
  set -f
  for group in $selected; do
    case "$group" in
      all) printf '%s\n' $all_groups ;;
      none) ;;
      *) printf '%s\n' "$group" ;;
    esac
  done
}

result="$(expand_groups | sort -u)"

if [[ -z $result ]]; then
  echo none
else
  printf '%s\n' "$result"
fi
