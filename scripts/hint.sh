#!/usr/bin/env bash
# Action `hint`: the native "hint pick" flow. The overlay re-renders the ORIGIN
# pane's visible text with hint labels overlaid in place on every openable
# token (pluck-style, context preserved); press the key (or Ctrl+click the
# token) to resolve + open it immediately.
#
# Latency design: the user must see the overlay INSTANTLY, but classifying
# every span is filesystem work (resolve + git lookups) that can take a
# second. So this action does only the cheap part inline - one `pane read`
# RPC, snapshot to a file - then opens the overlay and leaves the scan running
# in a BACKGROUND subshell that writes the token list atomically (tmp + mv).
# The overlay renders the raw snapshot immediately and overlays the hints the
# moment the list lands. Bare-name fuzzy tokens (any prose word matching one
# tracked file) are skipped by default: they are the noisiest kind and the
# most expensive to compute; QUICKLOOK_HINT_NAMES=1 re-enables them.
#
# WHY the scan cannot live in the overlay: `herdr pane read` is a server RPC,
# and a server RPC issued from inside a server-spawned overlay pane deadlocks.
# The origin repo rides as an env var, NOT --cwd: --cwd makes herdr resolve
# the pane's relative command against the repo and the pane flash-closes.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

load_config

ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

origin_pane=""
if command -v jq >/dev/null 2>&1; then
  origin_pane="$("$herdr_bin" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null)"
fi
if [ -z "$origin_pane" ] && [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  origin_pane="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty' 2>/dev/null || true)"
fi

# Is the hint being taken over a PREVIEW pane? If so a pick should push onto
# that preview's stack instead of spawning another surface. The question is
# asked HERE, in the action, because it needs a query-class RPC (`pane list`)
# and those are unsafe from inside the overlay pane that will act on the
# answer - so the overlay is handed the answer, not the question.
origin_preview=""
origin_cwd=""
if [ -n "$origin_pane" ]; then
  if origin_cwd="$(pane_is_preview "$origin_pane")"; then
    origin_preview=1
  else
    origin_cwd=""
  fi
fi

repo=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  repo="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
fi
[ -n "$repo" ] || repo="${HERDR_WORKSPACE_CWD:-}"

# Resolve tokens against the origin repo, same as the overlay's open step will.
[ -n "$repo" ] && [ -d "$repo" ] && cd "$repo" || true

clip="$(clip_read)"

raw_file="$(mktemp "${TMPDIR:-/tmp}/quicklook-hint-raw.XXXXXX")"
snap_file="$(mktemp "${TMPDIR:-/tmp}/quicklook-hint-snap.XXXXXX")"
tokens_file="${TMPDIR:-/tmp}/quicklook-hint-tok.$$"

if [ -n "$origin_pane" ]; then
  "$herdr_bin" pane read "$origin_pane" --source "${QUICKLOOK_PICK_SOURCE:-visible}" --format text 2>/dev/null >"$raw_file"
fi
_pick_strip_ansi <"$raw_file" >"$snap_file"

# Over a PREVIEW, the bottom row is less's prompt (our key-hint footer), not
# document content, and the scanner cannot tell. It was handing out letters
# for the footer's own text - the object name, and the `/` in "/ search",
# which opens the FILESYSTEM ROOT in the file viewer. Strip it from the SCAN
# only: the snapshot above keeps the footer so the overlay still looks like
# the pane, and dropping just the last row leaves every preceding line number
# unchanged, so the overlay's in-place hint positioning still lines up.
scan_file="$raw_file"
if [ -n "$origin_preview" ]; then
  scan_file="$(mktemp "${TMPDIR:-/tmp}/quicklook-hint-scan.XXXXXX")"
  strip_pager_footer <"$raw_file" >"$scan_file"
fi

# Clipboard-first, IMMEDIATE: the user who just selected+copied the exact
# token ON SCREEN wants it open, not a picker. Gated on the text actually
# being visible in the origin snapshot, so a stale clipboard from an hour ago
# never hijacks prefix+v. If it is visible and resolves, route it by type
# right now - directory to the real file-viewer, everything else (file/URL/
# SHA) through the preview pane - and never open the overlay.
if [ -n "$clip" ] && grep -qF -- "$clip" "$snap_file" 2>/dev/null; then
  if resolve_any_token "$clip" >/dev/null 2>&1; then
    rm -f "$raw_file" "$snap_file" 2>/dev/null
    if [ "${RESOLVED_MODE:-}" = "viewer" ]; then
      exec bash "$script_dir/open-in-viewer.sh" "$clip"
    fi
    # Determined token -> the roomy popup, same terminal as a hint pick.
    QUICKLOOK_PREVIEW_CWD="$PWD" exec bash "$script_dir/open-popup.sh" "$clip"
  fi
  # Visible but unresolvable (a partial or mistyped path): drop into the
  # fzf finder pre-seeded with it, instead of a hint overlay that cannot
  # open it either.
  if [[ "$clip" == */* || "$clip" == *.* ]]; then
    rm -f "$raw_file" "$snap_file" 2>/dev/null
    set -- plugin pane open \
      --plugin herdr-quicklook \
      --entrypoint find-pane \
      --placement overlay \
      --focus \
      --env "QUICKLOOK_FIND_QUERY=$clip"
    if [ -n "$repo" ] && [ -d "$repo" ]; then
      set -- "$@" --env "QUICKLOOK_FIND_CWD=$repo"
    fi
    exec "$herdr_bin" "$@"
  fi
fi

# Background scan. Token list line: `raw<TAB>line-no<TAB>osc8-uri<TAB>label`
# (URI precomputed here so the overlay's render loop never forks jq). Row 1 is
# the clipboard token when it resolves (line-no empty - it may not be on
# screen), deduped out of the on-screen rows. Written to .part, then mv'd:
# the overlay treats the file's existence as "scan done".
(
  # Shape-only classification (pluck's model): milliseconds, no filesystem;
  # resolution happens at open time. QUICKLOOK_HINT_VERIFIED=1 restores the
  # slower verified scan (and QUICKLOOK_HINT_NAMES=1 its bare-name fuzzy).
  if [ -z "${QUICKLOOK_HINT_VERIFIED:-}" ]; then
    export QUICKLOOK_SCAN_FAST=1
  fi
  [ -n "${QUICKLOOK_HINT_NAMES:-}" ] || export QUICKLOOK_SCAN_SKIP_NAMES=1
  {
    n=0
    while IFS=$'\t' read -r raw kind line_no; do
      [ -n "$raw" ] || continue
      printf '%s\t%s\t%s\t%-5s %s\n' "$raw" "$line_no" "$(quicklook_link_uri "$raw" || true)" "$kind" "$raw"
      n=$((n + 1))
      [ "$n" -ge "${#QUICKLOOK_HINT_KEYS}" ] && break
    done < <(pick_scan_text <"$scan_file")
  } >"$tokens_file.part"
  mv -f "$tokens_file.part" "$tokens_file"
  rm -f "$raw_file" 2>/dev/null
  [ "$scan_file" = "$raw_file" ] || rm -f "$scan_file" 2>/dev/null
) &

# Answer the viewer gate HERE, in the action's own context, and hand the
# result to the overlay: it saves the pane an RPC round trip on the hot
# pick path, and a failed gate would silently downgrade a directory pick
# from the real file viewer to a tree listing in the popup.
viewer_ok=0
"$herdr_bin" plugin action list --plugin herdr-file-viewer >/dev/null 2>&1 && viewer_ok=1

# Optional routing diagnostic (QUICKLOOK_DEBUG_LOG=1 in the plugin .env):
# the pane/action environment differs from a shell in ways that silently
# change routing, and this line is the difference between guessing and
# knowing which branch a pick took.
debug_log "hint: viewer_ok=$viewer_ok herdr_bin=$herdr_bin"

# Placement: overlay normally, POPUP when the origin is itself a preview
# overlay. Two overlays in one tab do NOT stack: herdr keeps the first on
# top, so a hint overlay opened over a preview overlay is focused but
# INVISIBLE - the user's presses fired (plugin log, exit 0, pane opened,
# focused:true), the buffer painted correctly, and the screen showed only
# the preview; their next keys then went into a pane they could not see. A
# popup is herdr's transient top surface and renders above overlays.
#
# Cost, per the overlay-vs-popup note in DESIGN.md: popup mouse input is
# forwarded raw to the process, so herdr-level OSC-8 Ctrl+click resolution
# is lost inside it. hint-pane's own SGR click tracking still works, and
# the keyboard path is untouched, which is the primary pick path anyway.
hint_placement=overlay
[ -n "$origin_preview" ] && hint_placement=popup

set -- plugin pane open \
  --plugin herdr-quicklook \
  --entrypoint hint-pane \
  --placement "$hint_placement" \
  --focus \
  --env "QUICKLOOK_VIEWER_OK=$viewer_ok" \
  --env "QUICKLOOK_DEBUG_LOG=${QUICKLOOK_DEBUG_LOG:-}" \
  --env "QUICKLOOK_HINT_TOKENS_FILE=$tokens_file" \
  --env "QUICKLOOK_HINT_SNAP_FILE=$snap_file" \
  --env "QUICKLOOK_ORIGIN_PANE=$origin_pane" \
  --env "QUICKLOOK_ORIGIN_PREVIEW=$origin_preview" \
  --env "QUICKLOOK_ORIGIN_CWD=$origin_cwd"

if [ -n "$repo" ] && [ -d "$repo" ]; then
  set -- "$@" --env "QUICKLOOK_HINT_CWD=$repo"
fi

# Near-full size so the popup's tty geometry stays close to the origin's:
# the snapshot was captured at the origin's width, and a much narrower
# popup would soft-wrap long rows and shift the mouse-click row mapping.
[ "$hint_placement" = popup ] && set -- "$@" --width 100% --height 100%

exec "$herdr_bin" "$@"
