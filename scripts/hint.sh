#!/usr/bin/env bash
# Action `hint`: the native, herdr-pluck-free "hint pick" flow. The overlay
# re-renders the ORIGIN pane's visible text with hint labels overlaid in place
# on every openable token (pluck-style, context preserved); press the key (or
# Ctrl+click the token) to resolve + open it immediately.
#
# WHY the scan happens HERE, not in the overlay: `herdr pane read` is a server
# RPC, and a server RPC issued from inside a server-spawned OVERLAY pane
# deadlocks (the overlay hangs forever). The ACTION script can issue RPCs fine
# (that is how it reads `herdr pane current`), so it reads the pane snapshot
# and runs the whole scan here, handing the overlay two files: the stripped
# snapshot text and the token list. The overlay then only renders and reads a
# keypress - no RPC, no hang.
#
# Origin pane id is captured BEFORE the overlay steals focus (once the overlay
# is focused, `pane current` returns the overlay). The origin repo rides as an
# env var, NOT --cwd: --cwd makes herdr resolve the pane's relative command
# against the repo and the pane flash-closes (file not found).
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

load_config

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

origin_pane=""
if command -v jq >/dev/null 2>&1; then
  origin_pane="$("$herdr_bin" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null)"
fi
if [ -z "$origin_pane" ] && [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  origin_pane="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)"
fi

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

# Resolve tokens against the origin repo, same as the overlay's open step will.
[ -n "$repo" ] && [ -d "$repo" ] && cd "$repo" || true

clip="$(clip_read)"

# One pane read, consumed twice: the ANSI-stripped snapshot is what the
# overlay re-renders (pick_scan_text's line numbers are indices into this
# same stripped text), and the raw text feeds the scanner.
raw_file="$(mktemp "${TMPDIR:-/tmp}/quicklook-hint-raw.XXXXXX")"
snap_file="$(mktemp "${TMPDIR:-/tmp}/quicklook-hint-snap.XXXXXX")"
tokens_file="$(mktemp "${TMPDIR:-/tmp}/quicklook-hint-tok.XXXXXX")"

if [ -n "$origin_pane" ]; then
  "$herdr_bin" pane read "$origin_pane" --source "${QUICKLOOK_PICK_SOURCE:-visible}" --format text 2>/dev/null >"$raw_file"
fi
_pick_strip_ansi <"$raw_file" >"$snap_file"

# Token list: `raw<TAB>line-no<TAB>label`. Row 1 is the clipboard token when
# it resolves (line-no empty - it may not be on screen), deduped out of the
# on-screen rows; the rest keep their snapshot line for in-place overlay.
{
  clip_raw=""
  if [ -n "$clip" ] && resolve_any_token "$clip" >/dev/null 2>&1; then
    clip_raw="$clip"
    printf '%s\t\t%s\n' "$clip" "clipboard: $clip"
  fi
  n=0
  while IFS=$'\t' read -r raw kind line_no; do
    [ -n "$raw" ] || continue
    [ -n "$clip_raw" ] && [ "$raw" = "$clip_raw" ] && continue
    printf '%s\t%s\t%-5s %s\n' "$raw" "$line_no" "$kind" "$raw"
    n=$((n + 1))
    [ "$n" -ge $(( ${#QUICKLOOK_HINT_KEYS} - 1 )) ] && break
  done < <(pick_scan_text <"$raw_file")
} >"$tokens_file"

rm -f "$raw_file" 2>/dev/null || true

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint hint-pane \
  --placement overlay \
  --focus \
  --env "QUICKLOOK_HINT_TOKENS_FILE=$tokens_file" \
  --env "QUICKLOOK_HINT_SNAP_FILE=$snap_file"

if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --env "QUICKLOOK_HINT_CWD=$repo"
fi

exec "$herdr_bin" "$@"
