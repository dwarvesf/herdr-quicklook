#!/usr/bin/env bash
# Action `hint`: the native, herdr-pluck-free "hint pick" flow. Overlays every
# openable token on screen with a one-key hint label; press the key to open the
# token immediately (resolve + preview), no fzf, no separate consume step.
#
# Same action/pane split as scripts/pick.sh (read its header): herdr runs an
# action with NO TTY, so the interactive keypress happens in the `hint-pane`
# overlay, not here. This script captures the ORIGIN pane id BEFORE the overlay
# steals focus, reads the clipboard token, and opens the overlay forwarding
# both via --env plus the origin cwd via --cwd.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

origin_pane=""
if command -v jq >/dev/null 2>&1; then
  origin_pane="$("$herdr_bin" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null)"
fi
if [ -z "$origin_pane" ] && [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  origin_pane="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)"
fi

clip="$(clip_read)"

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint hint-pane \
  --placement overlay \
  --focus

if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --cwd "$repo"
fi
if [ -n "$origin_pane" ]; then
  set -- "$@" --env "QUICKLOOK_HINT_ORIGIN_PANE=$origin_pane"
fi
if [ -n "$clip" ]; then
  set -- "$@" --env "QUICKLOOK_HINT_CLIP=$clip"
fi

exec "$herdr_bin" "$@"
