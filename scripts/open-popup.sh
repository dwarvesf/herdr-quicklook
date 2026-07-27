#!/usr/bin/env bash
# open-popup.sh: route a DETERMINED token - push it onto the origin
# preview's stack when there is one and the token is a file, else spawn a
# preview pane (addressable overlay by default),
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

# Gated execution trace: a pick runs this INSIDE a closing pane, where
# stderr goes nowhere and a die-on-source failure is indistinguishable from
# "nothing happened". The trace is the only visibility into that context.
if [ -n "${QUICKLOOK_DEBUG_LOG:-}" ]; then
  exec 2>>"${TMPDIR:-/tmp}/quicklook-popup-trace.log"
  set -x
fi

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
#
# When the push REFUSES (a `#123`, a SHA, a URL - anything `:e` cannot page,
# which on a PR preview is most of the top-ranked tokens), the fallback
# spawn below must NOT be an overlay: the origin preview is an overlay, two
# overlays in one tab do not stack, and the spawned pane would render
# invisibly BEHIND it - the same z-order failure the hint pane itself had.
# Force the popup surface for the fallback; an EXPLICIT placement (the
# uppercase pick's `tab`) still wins.
if [ "${QUICKLOOK_ORIGIN_PREVIEW:-}" = 1 ]; then
  push_resolved_into_pane "${QUICKLOOK_ORIGIN_PANE:-}" "$token" \
    "${QUICKLOOK_ORIGIN_CWD:-}" && exit 0
  QUICKLOOK_OPEN_PLACEMENT="${QUICKLOOK_OPEN_PLACEMENT:-popup}"
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
  # A popup is anonymous (not listed), so the spawned preview's name_pane
  # must not rename: `pane current` from inside it resolves to the pane
  # UNDERNEATH, and the rename poisons that pane's label (see name_pane).
  set -- "$@" --env "QUICKLOOK_ANON_PANE=1"
fi

if [ -n "${QUICKLOOK_PREVIEW_CWD:-$PWD}" ]; then
  set -- "$@" --env "QUICKLOOK_PREVIEW_CWD=${QUICKLOOK_PREVIEW_CWD:-$PWD}"
fi

# DETACHED spawn: this usually runs inside a hint pane that is about to
# close, and spawning while it still lives loses either way. An overlay born
# while the hint overlay exists renders UNDER it and stays under (first-wins
# z-order); a popup is refused outright when the hint pane IS the popup,
# because herdr allows one popup at a time ("popup already open", observed
# via the gated trace). The orphaned subshell survives this process's exit,
# its std fds are detached from the pane's pty so the pane can actually
# close, and by the time it spawns the hint pane is gone. The retry absorbs
# the window where herdr has not yet reaped the closing popup.
(
  # Ignore SIGHUP or the detachment is fiction: the pane's pty is torn down
  # the moment the parent exits, the kernel HUPs what is left of the
  # session, and the subshell died in its sleep - observed as "trace shows
  # exit 0, no spawn, no debug line".
  trap '' HUP
  sleep 0.25
  tries=0
  while :; do
    out="$("$herdr_bin" "$@" 2>&1)" && rc=0 || rc=$?
    debug_log "spawn: rc=$rc placement=$placement try=$tries out=${out:0:160}"
    case "$out" in
      *"popup already open"*)
        tries=$((tries + 1))
        [ "$tries" -lt 4 ] || break
        sleep 0.4
        ;;
      *) break ;;
    esac
  done
) </dev/null >/dev/null 2>&1 &
exit 0
