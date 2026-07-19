#!/usr/bin/env bash
# Action `find`: fuzzy-find a file to quick-look. Opens the find-pane overlay
# (fzf over the repo's tracked files, live bat preview while typing); Enter
# renders the pick through the same preview path as every other open.
#
# Same action/pane split as hint.sh: the action has no TTY, the overlay runs
# fzf. The origin cwd rides as an env var, never --cwd (--cwd breaks the
# pane's relative command resolution and the pane flash-closes).
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint find-pane \
  --placement overlay \
  --width 90% --height 90% \
  --focus

if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --env "QUICKLOOK_FIND_CWD=$repo"
fi

exec "$herdr_bin" "$@"
