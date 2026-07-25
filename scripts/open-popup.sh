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

herdr_bin="${HERDR_BIN_PATH:-herdr}"
token="${1:-}"
[ -n "$token" ] || exit 0

# QUICKLOOK_OPEN_PLACEMENT=tab opens a FULL persistent tab pane instead of
# the transient popup (the hint overlay's UPPERCASE pick).
placement="${QUICKLOOK_OPEN_PLACEMENT:-popup}"
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

# Not exec: the pane's LABEL is what the border shows, so name it after the
# object being previewed ("Preview: vcs.sh") instead of a generic "Preview".
# That is also why the renderer no longer draws a filename header row - the
# name lives in the chrome, where it costs no content line and cannot wrap.
out="$("$herdr_bin" "$@" 2>/dev/null)" || exit 0
printf '%s' "$out"

case "$token" in
  '#'*) label="PR ${token%% *}" ;;
  https://github.com/*/pull/*) label="PR #${token##*/}" ;;
  *) label="${token##*/}"; [ -n "$label" ] || label="$token" ;;
esac
# strip a :line suffix so the label stays the object's name
label="${label%%:*}"

if [ -n "$label" ] && command -v jq >/dev/null 2>&1; then
  pane="$(printf '%s' "$out" | jq -r '.result.plugin_pane.pane.pane_id // empty' 2>/dev/null)"
  [ -n "$pane" ] && "$herdr_bin" pane rename "$pane" "Preview: $label" >/dev/null 2>&1
fi
exit 0
