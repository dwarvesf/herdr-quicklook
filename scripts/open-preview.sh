#!/usr/bin/env bash
# Action `preview`: open the preview overlay pane, forwarding the origin
# workspace's cwd so relative paths resolve against the repo the user was in
# (the overlay itself becomes the focused pane once open).
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

# Capture the link-handler URL or caller token BEFORE any `set --` reassigns
# positional parameters (that clobbers $1 to the first herdr-command word).
token="${HERDR_PLUGIN_CLICKED_URL:-${1:-}}"

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint preview \
  --placement overlay \
  --focus

# env, never --cwd: --cwd breaks the pane's relative command resolution and
# the pane flash-closes (herdr resolves `bash scripts/...` against it).
if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --env "QUICKLOOK_PREVIEW_CWD=$repo"
fi

# Agent-push: a token argument rides into the pane as $QUICKLOOK_TOKEN (env is
# the only channel that crosses `plugin pane open`; the pane checks it before
# the clipboard). Only forwarded when the caller actually passed one.
if [ -n "$token" ]; then
  set -- "$@" --env "QUICKLOOK_TOKEN=$token"
fi

exec "$herdr_bin" "$@"
