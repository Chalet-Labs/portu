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
      # A value starting with - would reach git diff as an option.
      [[ -n ${2:-} && ${2:-} != -* ]] || usage
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

# A misspelled group would select a group no recipe runs, so every entry is checked before use.
rules="$(jq -r --arg known "core network ui app release all none" '
  ($known | split(" ")) as $known
  | .[]
  | if (.glob | type == "string" and length > 0)
      and (.groups | type == "array" and length > 0 and all(.[]; IN($known[])))
    then [.glob, (.groups | join(" "))] | @tsv
    else error("invalid entry \(tojson): needs a glob and groups from \($known | join(", "))")
    end' "$rules_file")"
if [[ -n $base ]]; then
  paths="$(changed_paths "$base")"
else
  paths="$(cat)"
fi

# Split on newlines, with globbing off. Not here-strings: bash needs a temp file for those, and where
# it can't create one (a sandboxed agent) the loop would silently select nothing.
set -f
selected=""
IFS=$'\n'
for path in $paths; do
  matched=0
  for rule in $rules; do
    glob="${rule%%$'\t'*}"
    # Unquoted on purpose: $glob is a pattern, and * also matches /.
    if [[ $path == $glob ]]; then
      matched=1
      selected+=" ${rule#*$'\t'}"
    fi
  done
  if [[ $matched -eq 0 ]]; then selected+=" $fallback"; fi
done
IFS=$' \t\n'

# A function, because bash 3.2 can't parse a case statement inside $( ).
expand_groups() {
  local group
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
