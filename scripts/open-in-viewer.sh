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
# Same gate as dir.sh's (sourced via lib.sh), so the QUICKLOOK_VIEWER_OK
# hint passed into a pane short-circuits it here too - this script is
# exec'd FROM the overlay, which may not reach `herdr` on its own.
if ! _dir_viewer_available; then
  notify "herdr-file-viewer not installed; opening the preview overlay"
  exec bash "$script_dir/open-preview.sh"
fi

# Token priority: $QUICKLOOK_TOKEN env > $1 (the overlay's `o` escalation and
# agent callers pass the file explicitly) > clipboard.
raw="$(pick_token "${1:-}")"
[ -z "$raw" ] && { notify "nothing to open (no token, clipboard empty)"; exit 0; }

# Base everything on the focused pane, not this script's own cwd.
# QUICKLOOK_KEEP_CWD=1 skips that cd: the hint overlay execs this script
# already standing in the ORIGIN repo, while `pane current` would report the
# overlay's own pane cwd (the wrong repo for the containment check below).
focused="$("$herdr_bin" pane current 2>/dev/null)"
fcwd="$(printf '%s' "$focused" | jq -r '.result.pane.cwd // empty' 2>/dev/null)"
if [ -z "${QUICKLOOK_KEEP_CWD:-}" ] && [ -n "$fcwd" ]; then cd "$fcwd" 2>/dev/null || true; fi

target=""
CLIP_LINE=""
if resolve_any_token "$raw"; then
  case "$RESOLVED_MODE" in
    browser)
      # Opening the browser is a successful open like any other mode (this
      # sub-goal's Outcome says "every successful open"); record before the
      # exit. See the matching comment in preview-pane.sh and DECISIONS.md.
      record_open "$raw"
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
      # naturally. This falls into the SAME re-root / control-char checks
      # below as a file target - a directory outside this repo's tree
      # opens a fresh viewer tab rooted at its own repo.
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

# A target INSIDE the focused repo reuses the plugin's own idempotent tab
# action below (open-or-switch, no duplicate viewer). A target OUTSIDE it
# needs a viewer rooted somewhere else, and the plugin action cannot do
# that: `plugin pane open` always roots at the FOCUSED pane, and the three
# ways to redirect it all fail (verified live, herdr 0.7.5 / file-viewer
# 1.14.0): `--cwd` breaks the spawn outright, because the viewer's manifest
# pane command is the relative `./target/release/herdr-file-viewer` and
# herdr resolves it against that cwd; an injected
# `--env HERDR_PLUGIN_CONTEXT_JSON` is overridden by herdr's own context;
# and the caller's cwd is ignored.
#
# What DOES work (also verified live): a PLAIN tab created at the target
# (`tab create --cwd`), then the viewer's binary run in it BY ABSOLUTE PATH.
# herdr injects no plugin context into a plain pane, so the viewer's own
# `from_env()` falls back to the process cwd and roots exactly there. The
# jump to a file+line rides `HERDR_FILE_VIEWER_OPEN` (the viewer's
# documented launch open-target), so this path needs no keystroke injection
# at all.
root="$(git rev-parse --show-toplevel 2>/dev/null)"
outside=0
if [ -z "$root" ] || { [ "$target" != "$root" ] && [[ "$target" != "$root"/* ]]; }; then
  outside=1
  tdir="$target"
  [ -d "$tdir" ] || tdir="${target%/*}"
  root="$(git -C "$tdir" rev-parse --show-toplevel 2>/dev/null)"
  [ -z "$root" ] && root="$tdir"
fi
rel="${target#"$root"/}"
[ "$rel" = "$target" ] && rel=""

# $rel reaches the file-viewer either as send-text keystrokes (in-repo) or as
# an env open-target (outside); a control byte in the filename would inject
# keystrokes into that plugin. Refuse BEFORE either branch consumes it, so
# the guard cannot be bypassed by a future edit to only one path.
case "$rel" in
  *[$'\n\r\t']*) notify "unsafe filename (control chars); refusing"; exit 0 ;;
esac

if [ "$outside" -eq 1 ]; then
  vbin="$(viewer_bin)" || {
    notify "file viewer binary not built; opening the preview instead"
    exec bash "$script_dir/open-preview.sh" "$raw"
  }
  # A fresh tab per outside target is deliberate: the idempotent action
  # would hand back a viewer rooted at the WRONG repo.
  set -- tab create --cwd "$root" --focus
  [ -n "$rel" ] && set -- "$@" --env "HERDR_FILE_VIEWER_OPEN=$rel${CLIP_LINE:+:$CLIP_LINE}"
  vpane="$("$herdr_bin" "$@" 2>/dev/null | jq -r '.result.root_pane.pane_id // empty' 2>/dev/null)"
  [ -n "$vpane" ] || {
    notify "could not open a viewer tab; opening the preview instead"
    exec bash "$script_dir/open-preview.sh" "$raw"
  }
  "$herdr_bin" pane run "$vpane" "$vbin" >/dev/null 2>&1 \
    || { notify "file viewer did not start"; exit 1; }
  notify "viewer rooted at $root (outside this repo)"
  record_open "$raw"
  exit 0
fi

# The viewer opens in its OWN TAB (open-file-viewer-tab switches to an
# existing viewer tab instead of opening twice): a vertical split would
# disrupt the origin tab's layout. After the action, focus lands on the
# viewer pane; poll `pane current` until its label reads "Files".
"$herdr_bin" plugin action invoke open-file-viewer-tab --plugin herdr-file-viewer >/dev/null 2>&1 \
  || { notify "herdr-file-viewer is not installed"; exit 1; }
pid=""
for _ in $(seq 1 20); do
  pid="$("$herdr_bin" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null)"
  if [ -n "$pid" ]; then
    label="$("$herdr_bin" pane list 2>/dev/null \
      | jq -r --arg id "$pid" '.result.panes[] | select(.pane_id == $id) | .label // empty' 2>/dev/null)"
    [ "$label" = "Files" ] && break
  fi
  pid=""
  sleep 0.15
done
[ -z "$pid" ] && { notify "file viewer did not open"; exit 1; }
sleep 0.5 # let the TUI finish its first tree walk before it eats keys

# rel empty = the target IS the repo root; the viewer already opened rooted
# there, so there is nothing to goto.
if [ -n "$rel" ]; then
  "$herdr_bin" pane send-keys "$pid" f >/dev/null 2>&1
  "$herdr_bin" pane send-text "$pid" "$rel" >/dev/null 2>&1
  "$herdr_bin" pane send-keys "$pid" Enter >/dev/null 2>&1
fi

if [ -n "$CLIP_LINE" ]; then
  sleep 0.2
  "$herdr_bin" pane send-text "$pid" ":" >/dev/null 2>&1
  "$herdr_bin" pane send-text "$pid" "$CLIP_LINE" >/dev/null 2>&1
  "$herdr_bin" pane send-keys "$pid" Enter >/dev/null 2>&1
fi

record_open "$raw"
