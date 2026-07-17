#!/usr/bin/env bash
# Action `agent-suggestion`: open the newest token recorded by the opt-in
# agent-status hook using the cwd of the pane that produced it.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

state_root="${HERDR_PLUGIN_STATE_DIR:-$(recents_state_dir)}/agent-suggestions"
latest="$state_root/latest.json"
if [ ! -f "$latest" ] || ! command -v jq >/dev/null 2>&1; then
  "$herdr_bin" notification show "quicklook" --body "No agent suggestion is available" >/dev/null 2>&1 || true
  exit 0
fi

token="$(jq -r '.token // empty' "$latest" 2>/dev/null || true)"
cwd="$(jq -r '.cwd // empty' "$latest" 2>/dev/null || true)"
if [ -z "$token" ] || [[ "$token" =~ [[:cntrl:]] ]]; then
  "$herdr_bin" notification show "quicklook" --body "The latest agent suggestion is invalid" >/dev/null 2>&1 || true
  exit 0
fi

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint preview \
  --placement overlay \
  --focus \
  --env "QUICKLOOK_TOKEN=$token"
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  set -- "$@" --cwd "$cwd"
fi

exec "$herdr_bin" "$@"
