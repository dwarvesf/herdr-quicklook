#!/usr/bin/env bash
# pr-view.sh <pr-ref>: `gh pr view`, laid out for reading.
#
#   PR #65 · <title>  [MERGED]     <- title row, like bat's file header
#   author/number/url/... (non-empty only)
#   ------------------------------ <- rule
#   <body rendered as markdown>    <- what a PR body actually is
#
# gh prints labels/assignees/reviewers/projects/milestone even when empty,
# which was half the pane; those rows are dropped. QUICKLOOK_PR_RAW=1
# prints gh's output verbatim instead.
#
# A script rather than a pipeline in RESOLVED_CMD: the handler contract
# passes an argv ARRAY (no shell), so a pipe needs a real program. The ref
# arrives as one argv element and is never re-parsed by a shell.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"
load_config_env

ref="${1:-}"
[ -n "$ref" ] || exit 0

out="$(gh pr view "$ref" 2>&1)" || { printf '%s\n' "$out"; exit 0; }

if [ -n "${QUICKLOOK_PR_RAW:-}" ]; then
  printf '%s\n' "$out"
  exit 0
fi

# gh separates its metadata block from the markdown body with a lone "--".
head_block="${out%%$'\n'--$'\n'*}"
if [ "$head_block" = "$out" ]; then
  printf '%s\n' "$out"
  exit 0
fi
body="${out#*$'\n'--$'\n'}"

cols="$(tput cols 2>/dev/null)" || cols=100
case "$cols" in '' | *[!0-9]*) cols=100 ;; esac
[ "$cols" -gt 120 ] && cols=120

# field <name> -> that field's value (gh prints "name<TAB>value").
field() {
  printf '%s\n' "$head_block" | awk -F'\t' -v k="$1:" '$1 == k { print $2; exit }'
}

BOLD=$'\033[1m'
DIM=$'\033[2m'
OFF=$'\033[0m'
title="$(field title)"
state="$(field state)"
number="$(field number)"

# Title row first, so the pane says WHAT this is before any metadata.
printf '%s%s%s  %s%s%s\n' \
  "$BOLD" "${number:+PR #$number · }$title" "$OFF" "$DIM" "${state:+[$state]}" "$OFF"

# Metadata: skip title/state (already in the header above) and every field
# gh printed with no value.
printf '%s\n' "$head_block" | awk -F'\t' '
  $1 == "title:" || $1 == "state:" { next }
  { v = $2; gsub(/^[ \t]+|[ \t]+$/, "", v) }
  v == "" { next }
  { printf "%-12s %s\n", $1, v }
'

# Rule between metadata and body: they are different kinds of content and
# ran together as one wall of text before.
# ${rule} braces are load-bearing: Apple's bash 3.2 parses the multibyte
# rule character as part of the VARIABLE NAME in "$rule─", and dies with
# `unbound variable: rule─` under set -u. Homebrew bash 5 does not, so this
# only breaks where a pane runs /bin/bash.
rule=""
i=0
while [ "$i" -lt "$cols" ]; do
  rule="${rule}─"
  i=$((i + 1))
done
printf '%s%s%s\n' "$DIM" "$rule" "$OFF"

if command -v glow >/dev/null 2>&1; then
  # same style resolution as the markdown renderer, so a PR body and a .md
  # preview look identical (the viewer's palette when it is installed).
  printf '%s\n' "$body" | glow -s "$(_markdown_glow_style)" -w "$cols" - 2>/dev/null \
    || printf '%s\n' "$body"
else
  printf '\n%s\n' "$body"
fi
