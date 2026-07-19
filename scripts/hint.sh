#!/usr/bin/env bash
# Action `hint`: the native, herdr-pluck-free "hint pick" flow. Overlays every
# openable token on screen with a one-key hint label; press the key to open the
# token immediately (resolve + preview), no fzf, no separate consume step.
#
# WHY the scan happens HERE, not in the overlay: `herdr pane read` (pick_acquire)
# is a server RPC, and a server RPC issued from inside a server-spawned OVERLAY
# pane deadlocks (the overlay hangs forever). The ACTION script can issue RPCs
# fine (that is how it reads `herdr pane current`), so it does the whole scan and
# hands the finished token+label list to the overlay via a temp file. The overlay
# then only renders and reads a keypress - no RPC, no hang.
#
# Origin pane id is captured BEFORE the overlay steals focus (see the pick.sh
# header for the focus race). The origin repo rides as an env var, NOT --cwd:
# --cwd makes herdr resolve the pane's relative command against the repo and the
# pane flash-closes (file not found).
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

# Build the ordered "raw<TAB>label" list. Row 1 is the clipboard token when it
# resolves; the rest are the ranked on-screen candidates, clipboard deduped out.
tokens_file="$(mktemp "${TMPDIR:-/tmp}/quicklook-hint.XXXXXX")"
{
  clip_raw=""
  if [ -n "$clip" ] && resolve_any_token "$clip" >/dev/null 2>&1; then
    clip_raw="$clip"
    printf '%s\t%s\n' "$clip" "clipboard  $clip"
  fi
  n=0
  while IFS=$'\t' read -r raw kind line_no; do
    [ -n "$raw" ] || continue
    [ -n "$clip_raw" ] && [ "$raw" = "$clip_raw" ] && continue
    printf '%s\t%s\n' "$raw" "$(printf '%-5s L%-4s %s' "$kind" "$line_no" "$raw")"
    n=$((n + 1))
    [ "$n" -ge 25 ] && break
  done < <(pick_acquire "$origin_pane")
} >"$tokens_file"

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint hint-pane \
  --placement overlay \
  --focus \
  --env "QUICKLOOK_HINT_TOKENS_FILE=$tokens_file"

if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --env "QUICKLOOK_HINT_CWD=$repo"
fi

exec "$herdr_bin" "$@"
