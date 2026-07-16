#!/usr/bin/env bash
# Pane `preview`: runs inside the overlay (real TTY). Reads the clipboard,
# resolves it, renders with bat (fallback: less). URLs open the browser and
# the overlay closes itself. Bare filenames search the repo's tracked files
# (one hit opens, several become an fzf pick). q or Esc-Esc closes.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
. "$script_dir/lib.sh"

pause_close() {
  printf '%s\n' "$*"
  read -r -n1 -p "press any key to close" _ 2>/dev/null || sleep 2
  exit 0
}

load_config

# Token priority: $QUICKLOOK_TOKEN env (agents set this via `plugin pane open
# --env`) > $1 > clipboard. Lets an agent push a file onto the screen.
raw="$(pick_token "${1:-}")"
[ -z "$raw" ] && pause_close "quicklook: nothing to open (no token, clipboard empty)"

target=""
CLIP_LINE=""
if resolve_any_token "$raw"; then
  case "$RESOLVED_MODE" in
    browser) url_open "$RESOLVED_TARGET"; exit 0 ;;
  esac
  target="$RESOLVED_TARGET"
  CLIP_LINE="$RESOLVED_LINE"
else
  # Only a path-shaped token reaches here (github/url always resolve one way
  # or another via resolve_any_token): fall back to the interactive
  # bare-name search over this repo's tracked files.
  parse_token "$raw"
  handle_bare_name "$CLIP_PATH" && {
    target="$RESOLVED_TARGET"
    CLIP_LINE="$RESOLVED_LINE"
  }
fi

[ -z "${target:-}" ] && pause_close "quicklook: not a file I can find: $raw" \
  "(tried as-is, \$PWD, this repo's worktrees, QUICKLOOK_ROOTS, repo filename search)"

record_open "$raw"

# Render with less driving the real FILE (not a bat pipe), so less keeps the
# filename and its `visual` command works: `o` (or `v`) escalates to the
# herdr-file-viewer pane via scripts/escalate.sh. bat becomes the LESSOPEN
# preprocessor for syntax highlighting; without bat, plain less -N.
lesskey_args=()
[ -f "$script_dir/../lesskey" ] && lesskey_args=(--lesskey-src="$script_dir/../lesskey")

export VISUAL="$script_dir/escalate.sh"
if command -v bat >/dev/null 2>&1; then
  export LESSOPEN='|bat --color=always --style=numbers,header %s'
  exec less -R "${lesskey_args[@]}" ${CLIP_LINE:++$CLIP_LINE} "$target"
fi
exec less -N "${lesskey_args[@]}" ${CLIP_LINE:++$CLIP_LINE} "$target"
