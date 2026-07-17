#!/usr/bin/env bash
# Action `pick`: opens the `pick-pane` overlay, the native one-key
# "see everything openable on screen -> pick -> open" flow (v0.5).
#
# herdr runs an action's own command WITHOUT a TTY (the same constraint
# scripts/recents.sh documents for its own picker) - so the interactive fzf
# step cannot run here. This script only:
#   1. captures the ORIGIN pane id, BEFORE the overlay opens. `herdr pane
#      current` returns the FOCUSED pane; the instant pick-pane is focused,
#      that becomes the overlay, not the origin (see HANDOFF.md). `herdr
#      pane read <id>` takes an explicit id and is focus-independent, so
#      pick-pane.sh scans with the id forwarded here.
#   2. reads the clipboard token, for the clipboard-first preselected row.
#   3. opens the pick-pane overlay, forwarding the origin pane id + cwd +
#      clipboard token via --env/--cwd.
# Mirrors scripts/recents.sh's action/pane split verbatim.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

# 1. Origin pane id, captured HERE - before focus moves to the overlay.
origin_pane=""
if command -v jq >/dev/null 2>&1; then
  origin_pane="$("$herdr_bin" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null)"
fi
if [ -z "$origin_pane" ] && [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  # Fallback when `pane current` is unavailable: the context JSON's own
  # focused-pane field, same shape as the .focused_pane_cwd fallback below.
  origin_pane="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)"
fi

# 2. The clipboard token, forwarded so pick-pane.sh doesn't need its own
# clipboard read.
clip="$(clip_read)"

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint pick-pane \
  --placement overlay \
  --focus

if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --cwd "$repo"
fi

if [ -n "$origin_pane" ]; then
  set -- "$@" --env "QUICKLOOK_PICK_ORIGIN_PANE=$origin_pane"
fi

if [ -n "$clip" ]; then
  set -- "$@" --env "QUICKLOOK_PICK_CLIP=$clip"
fi

exec "$herdr_bin" "$@"
