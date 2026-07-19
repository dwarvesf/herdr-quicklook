#!/usr/bin/env bash
# Action `recents`: reopen the most recently quick-looked token, or fzf-pick
# among the last N when fzf is installed.
#
# herdr runs an action's own command WITHOUT a TTY (the same constraint every
# other action in this plugin is built around, and the installed
# jt.command-palette plugin's open.sh documents identically for its own
# fzf-driven picker) - so the interactive pick cannot run here directly. This
# script only opens the `recents-pick` overlay pane (scripts/recents-pane.sh
# below), which DOES get a TTY, forwarding the origin workspace's cwd the
# same way scripts/open-preview.sh does, so a relative token in the recents
# log resolves against the repo the user was actually in.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint recents-pick \
  --placement overlay \
  --width 90% --height 90% \
  --focus

if [ -n "$repo" ] && [ -d "$repo" ]; then
  # env, never --cwd: --cwd flash-closes the pane (relative command resolution).
  set -- "$@" --env "QUICKLOOK_PREVIEW_CWD=$repo"
fi

exec "$herdr_bin" "$@"
