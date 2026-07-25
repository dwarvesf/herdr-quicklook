#!/usr/bin/env bash
# pr-view.sh <pr-ref>: `gh pr view` with the BODY rendered as markdown
# (glow), which is what a PR body is. The fields above the body are plain
# text and pass through untouched. QUICKLOOK_PR_RAW=1 (or glow absent)
# falls back to gh's raw output.
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

if [ -n "${QUICKLOOK_PR_RAW:-}" ] || ! command -v glow >/dev/null 2>&1; then
  printf '%s\n' "$out"
  exit 0
fi

# gh separates its metadata block from the markdown body with a lone "--".
head="${out%%$'\n'--$'\n'*}"
if [ "$head" = "$out" ]; then
  printf '%s\n' "$out"
  exit 0
fi
body="${out#*$'\n'--$'\n'}"

cols="$(tput cols 2>/dev/null)" || cols=100
printf '%s\n\n' "$head"
# same style resolution as the markdown renderer, so a PR body and a .md
# preview look identical (the viewer's palette when it is installed).
printf '%s\n' "$body" | glow -s "$(_markdown_glow_style)" -w "${cols:-100}" - 2>/dev/null \
  || printf '%s\n' "$body"
