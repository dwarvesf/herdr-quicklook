#!/usr/bin/env bash
# Link-handler action for OSC-8 sentinel URLs emitted by the hint overlay (and formerly linkify-pane).
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

clicked="${HERDR_PLUGIN_CLICKED_URL:-${1:-}}"
if ! token="$(quicklook_token_from_link "$clicked")"; then
  "$herdr_bin" notification show "quicklook" --body "Refused an invalid quicklook link" >/dev/null 2>&1 || true
  exit 1
fi

unset HERDR_PLUGIN_CLICKED_URL HERDR_PLUGIN_LINK_HANDLER_ID

# PUSH, not spawn: when the click came from a preview pane that is already
# paging a file, drive THAT pane's less instead of stacking another overlay
# on the screen. `:e <path>` appends to less's file list and jumps to it, so
# the pane's own file list becomes the preview stack (remove-file, bound to
# `,` and Backspace in lesskey, pops back). Driving another pane's keys is
# the same mechanism open-in-viewer.sh uses on the file-viewer pane.
#
# Everything degrades to the old spawn: a click from a non-preview pane, a
# token that is not a local file (a URL belongs in the browser, a SHA in
# `git show`), or no jq/pane id at all.
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
clicked_pane=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  clicked_pane="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)"
fi
push_into_preview "$clicked_pane" "$token" && exit 0

exec bash "$script_dir/open-preview.sh" "$token"
