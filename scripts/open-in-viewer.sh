#!/usr/bin/env bash
# Action `open-in-viewer`: open the clipboard's path INSIDE the
# herdr-file-viewer plugin pane (requires that plugin to be installed).
#
# The viewer has no goto-file API, so this drives its own keys over the herdr
# socket: ensure a "Files" pane exists in the focused tab, then
# send-keys f -> send-text <repo-relative path> -> Enter (+ :line Enter for
# "path:123"). UI-scripting by nature; revisit if the viewer's keymap changes.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

notify() {
  "$herdr_bin" notification show "quicklook" --body "$1" --sound none >/dev/null 2>&1
}

load_config

# Soft dependency: without herdr-file-viewer this action degrades to the
# preview overlay instead of failing, so the binding still does something useful.
if ! "$herdr_bin" plugin action list --plugin herdr-file-viewer >/dev/null 2>&1; then
  notify "herdr-file-viewer not installed; opening the preview overlay"
  exec bash "$script_dir/open-preview.sh"
fi

# Token priority: $QUICKLOOK_TOKEN env > $1 (the overlay's `o` escalation and
# agent callers pass the file explicitly) > clipboard.
raw="$(pick_token "${1:-}")"
[ -z "$raw" ] && { notify "nothing to open (no token, clipboard empty)"; exit 0; }

# Base everything on the focused pane, not this script's own cwd
focused="$("$herdr_bin" pane current 2>/dev/null)"
fcwd="$(printf '%s' "$focused" | jq -r '.result.pane.cwd // empty' 2>/dev/null)"
if [ -n "$fcwd" ]; then cd "$fcwd" 2>/dev/null || true; fi

target=""
CLIP_LINE=""
if resolve_any_token "$raw"; then
  case "$RESOLVED_MODE" in
    browser)
      url_open "$RESOLVED_TARGET"
      exit 0
      ;;
    command)
      # This script has no pager of its own (it only drives OTHER panes over
      # the herdr socket, see the header comment); command-mode output needs
      # a real TTY. Re-resolving the SAME raw token in the preview overlay is
      # safe here specifically: a command-mode token (SHA / #123 / PR URL)
      # doesn't depend on a filesystem test, so resolve_any_token reproduces
      # the identical RESOLVED_CMD there deterministically. Dispatch BEFORE
      # the empty-target guard below: a real command-mode result legitimately
      # leaves RESOLVED_TARGET empty.
      if [ "${#RESOLVED_CMD[@]}" -gt 0 ]; then
        record_open "$raw"
        exec bash "$script_dir/open-preview.sh" "$raw"
      fi
      # RESOLVED_CMD empty is a handler bug; fall through to "not found".
      ;;
    viewer)
      # RESOLVED_TARGET is a directory. herdr-file-viewer is confirmed
      # installed already (the soft-dependency gate at the top of this
      # script degrades to the preview overlay before we ever reach here
      # otherwise), so dir.sh always emits `viewer` in this context - reuse
      # the SAME goto-path send-keys sequence the file case below already
      # uses and tests (f -> type <repo-relative path> -> Enter) to land the
      # viewer's cursor on the directory; there is no separate "root at a
      # directory" verb in the socket protocol. Directories have no line
      # number, so CLIP_LINE stays empty and the `:N` step below is skipped
      # naturally. This falls into the SAME containment / control-char
      # checks below as a file target - a directory outside this repo's
      # tree still gets "outside this repo's tree: use the preview overlay
      # instead".
      target="$RESOLVED_TARGET"
      CLIP_LINE=""
      ;;
    *)
      target="$RESOLVED_TARGET"
      CLIP_LINE="$RESOLVED_LINE"
      ;;
  esac
fi
[ -z "${target:-}" ] && { notify "not found: $raw"; exit 0; }

# The viewer roots at the focused pane's repo; outside targets can't show there.
root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$root" ] || [[ "$target" != "$root"/* ]]; then
  notify "outside this repo's tree: use the preview overlay instead"
  exit 0
fi
rel="${target#"$root"/}"

# $rel is typed into the file-viewer TUI via send-text; a control byte in the
# filename (e.g. an embedded newline in a maliciously-named file) would inject
# extra keystrokes into that plugin. Refuse.
case "$rel" in
  *[$'\n\r\t']*) notify "unsafe filename (control chars); refusing"; exit 0 ;;
esac

tab="$(printf '%s' "$focused" | jq -r '.result.pane.tab_id // empty' 2>/dev/null)"
files_pane() {
  "$herdr_bin" pane list 2>/dev/null \
    | jq -r --arg tab "$tab" \
        '.result.panes[] | select(.label == "Files" and .tab_id == $tab) | .pane_id' \
    | head -1
}

pid="$(files_pane)"
if [ -z "$pid" ]; then
  "$herdr_bin" plugin action invoke open-file-viewer --plugin herdr-file-viewer >/dev/null 2>&1 \
    || { notify "herdr-file-viewer is not installed"; exit 1; }
  for _ in $(seq 1 20); do
    pid="$(files_pane)"
    [ -n "$pid" ] && break
    sleep 0.15
  done
  [ -z "$pid" ] && { notify "file viewer did not open"; exit 1; }
  sleep 0.5 # let the TUI finish its first tree walk before it eats keys
else
  # focus without toggling: zoom on/off, the viewer launcher's own trick
  "$herdr_bin" pane zoom "$pid" --on >/dev/null 2>&1
  "$herdr_bin" pane zoom "$pid" --off >/dev/null 2>&1
fi

"$herdr_bin" pane send-keys "$pid" f >/dev/null 2>&1
"$herdr_bin" pane send-text "$pid" "$rel" >/dev/null 2>&1
"$herdr_bin" pane send-keys "$pid" Enter >/dev/null 2>&1

if [ -n "$CLIP_LINE" ]; then
  sleep 0.2
  "$herdr_bin" pane send-text "$pid" ":" >/dev/null 2>&1
  "$herdr_bin" pane send-text "$pid" "$CLIP_LINE" >/dev/null 2>&1
  "$herdr_bin" pane send-keys "$pid" Enter >/dev/null 2>&1
fi

record_open "$raw"
