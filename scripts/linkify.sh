#!/usr/bin/env bash
# Action `linkify`: capture the origin pane before opening a TTY overlay that
# renders its openable tokens as Ctrl-clickable OSC-8 links.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"
origin="${HERDR_PANE_ID:-}"
repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  origin="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)"
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
if [ -z "$origin" ] && command -v jq >/dev/null 2>&1; then
  origin="$("$herdr_bin" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null || true)"
fi

if [ -z "$origin" ]; then
  "$herdr_bin" notification show "quicklook" --body "No terminal pane is available to linkify" >/dev/null 2>&1 || true
  exit 0
fi

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint linkify-pane \
  --placement overlay \
  --focus \
  --env "QUICKLOOK_LINKIFY_ORIGIN_PANE=$origin"

if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --cwd "$repo"
fi

exec "$herdr_bin" "$@"
