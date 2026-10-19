#!/usr/bin/env bash
# Prints the test groups that changed paths can affect, one per line, sorted.
# The rules live in script/test-scope.json: every rule whose glob matches a path adds its groups,
# and a path that no rule matches selects every group. `just test-affected` and PR CI read this.
#
# Usage:
#   script/test_scope.sh --base <ref>     <ref>...HEAD plus staged, unstaged and untracked files
#   script/test_scope.sh --paths-from -   newline-separated paths on stdin
#   --no-fallback                         a path no rule matches selects nothing (for the guard test)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rules_file="$script_dir/test-scope.json"
all_groups="core network ui app release"

usage() {
  echo "usage: script/test_scope.sh [--no-fallback] --base <ref> | --paths-from -" >&2
  exit 2
}

repo_git() { git -C "$script_dir/.." -c core.quotePath=false "$@"; }

# --no-renames lists both sides of a move, so a file moved out of a package still selects it.
changed_paths() {
  repo_git diff --name-only --no-renames "$1...HEAD" &&
    repo_git diff --name-only --no-renames --cached &&
    repo_git diff --name-only --no-renames &&
    repo_git ls-files --others --exclude-standard
}

base=""
from_stdin=0
fallback="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ -n ${2:-} ]] || usage
      base="$2"
      shift 2
      ;;
    --paths-from)
      [[ ${2:-} == - ]] || usage
      from_stdin=1
      shift 2
      ;;
    --no-fallback)
      fallback=""
      shift
      ;;
    *) usage ;;
  esac
done
if [[ -n $base && $from_stdin -eq 1 ]] || [[ -z $base && $from_stdin -eq 0 ]]; then usage; fi

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
  if [[ $matched -eq 0 ]]; then selected+=" $fallback"; fi
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
