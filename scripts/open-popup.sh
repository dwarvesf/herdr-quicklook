#!/usr/bin/env bash
# open-popup.sh: open a DETERMINED token in herdr's native 90% popup surface,
# running the preview renderer (so every render type, o/e/d, and the recents
# log come along). This is the terminal of the hint flow: once the overlay
# (or the clipboard gate) has settled on one token, the render belongs in a
# roomy popup, not the pane-hugging overlay.
#
# Callable from an ACTION context or from INSIDE an overlay pane: `plugin
# pane open` is a spawn-class request (immediate ack), not a blocking query
# like `pane read`, the one RPC family that deadlocks from an overlay (see
# hint.sh; same precedent as escalate.sh driving the file-viewer).
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

token="${1:-}"
[ -n "$token" ] || exit 0

# Picked from INSIDE a preview? Then push onto that preview's stack rather
# than opening a second surface, so a hint drill-down stacks exactly like a
# Ctrl+click does. hint.sh answered the "is it a preview" question for us in
# the action context, because it needs a query RPC and we are running inside
# an overlay pane where those are unsafe. This call is write-only.
if [ "${QUICKLOOK_ORIGIN_PREVIEW:-}" = 1 ]; then
  push_resolved_into_pane "${QUICKLOOK_ORIGIN_PANE:-}" "$token" \
    "${QUICKLOOK_ORIGIN_CWD:-}" && exit 0
fi

# QUICKLOOK_OPEN_PLACEMENT=tab opens a FULL persistent tab pane (the hint
# overlay's UPPERCASE pick); =popup restores the old transient 90% popup.
#
# The default is `overlay`, not `popup`, because a POPUP IS ANONYMOUS:
# `plugin pane open --placement popup` returns {"result":{"type":"ok"}} with
# no pane_id, and the pane never appears in `pane list` at all. Measured
# against herdr 0.7.5; tab and overlay both return an id and are listed.
#
# Everything that makes a preview drillable needs that identity:
#   - `hint` finds its origin pane by id, so from inside a popup there is no
#     second hint overlay - the pick is a dead end,
#   - pane_is_preview matches on the pane's label, so a pick taken in a popup
#     could not push onto its stack and spawned yet another surface.
# A popup buys some extra room and costs the whole drill-down loop, which is
# the wrong trade for the common path.
placement="${QUICKLOOK_OPEN_PLACEMENT:-overlay}"
set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint preview \
  --placement "$placement" \
  --focus \
  --env "QUICKLOOK_TOKEN=$token"
if [ "$placement" = "popup" ]; then
  set -- "$@" --width 90% --height 90%
fi

if [ -n "${QUICKLOOK_PREVIEW_CWD:-$PWD}" ]; then
  set -- "$@" --env "QUICKLOOK_PREVIEW_CWD=${QUICKLOOK_PREVIEW_CWD:-$PWD}"
fi

exec "$herdr_bin" "$@"
