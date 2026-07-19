#!/usr/bin/env bash
# Link-handler action for OSC-8 sentinel URLs emitted by linkify-pane.sh.
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
exec bash "$script_dir/open-preview.sh" "$token"
