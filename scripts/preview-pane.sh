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

# Enter the origin repo (forwarded as env, never --cwd: --cwd flash-closes
# the pane) so relative tokens resolve against the repo the user was in.
if [ -n "${QUICKLOOK_PREVIEW_CWD:-}" ] && [ -d "$QUICKLOOK_PREVIEW_CWD" ]; then
  cd "$QUICKLOOK_PREVIEW_CWD" || true
fi

# Token priority: $QUICKLOOK_TOKEN env (agents set this via `plugin pane open
# --env`) > $1 > clipboard. Lets an agent push a file onto the screen.
raw="$(pick_token "${1:-}")"
[ -z "$raw" ] && pause_close "quicklook: nothing to open (no token, clipboard empty)"

target=""
CLIP_LINE=""
if resolve_any_token "$raw"; then
  case "$RESOLVED_MODE" in
    browser)
      # Opening the browser is a successful open like any other mode (this
      # sub-goal's Outcome says "every successful open"); record before the
      # exit, not after - SG-01's original placement here reached
      # url_open+exit before either pane script's own record_open call site,
      # so a browsed URL was never recorded. See DECISIONS.md.
      record_open "$raw"
      url_open "$RESOLVED_TARGET"
      exit 0
      ;;
    command)
      # RESOLVED_CMD is the argv (a bash array, never a flattened string ,
      # see the contract comment at the top of lib.sh). Dispatch BEFORE the
      # empty-target guard below: a real command-mode result legitimately
      # has an empty RESOLVED_TARGET (it uses RESOLVED_CMD instead), so
      # falling into that guard would wrongly report "not a file I can
      # find" for a successful resolution.
      if [ "${#RESOLVED_CMD[@]}" -gt 0 ]; then
        record_open "$raw"
        render_command_in_pager "${RESOLVED_CMD[@]}"
        exit $?
      fi
      # RESOLVED_CMD empty is a handler bug (claimed command mode with no
      # argv to run); fall through and treat it like an unresolved token.
      ;;
    viewer)
      # RESOLVED_TARGET is a directory. This popup has no way to drive
      # ANOTHER pane's herdr-file-viewer socket (it only has its own TTY, a
      # pager) - that real rooting happens in open-in-viewer.sh's own viewer
      # arm instead. Never fall through to the file-render path below on a
      # directory target, that is the exact `exec less <directory>` bug this
      # arm exists to prevent. Safe degrade: page a tree/listing of it
      # instead, the same shape dir.sh falls back to itself when
      # herdr-file-viewer isn't installed at all (RESOLVED_MODE=command).
      record_open "$raw"
      if command -v eza >/dev/null 2>&1; then
        render_command_in_pager eza --tree "$RESOLVED_TARGET"
      else
        render_command_in_pager ls -la "$RESOLVED_TARGET"
      fi
      exit $?
      ;;
    *)
      target="$RESOLVED_TARGET"
      CLIP_LINE="$RESOLVED_LINE"
      ;;
  esac
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
  "(tried as-is, \$PWD, this repo's worktrees, QUICKLOOK_ROOTS, the workspace sweep incl. other repos' worktrees, repo filename search)"

record_open "$raw"

# Render through the render registry (scripts/renderers/, contract
# documented in lib.sh next to the handler-registry one): render_any walks
# RENDER_KINDS and dispatches to the first renderer whose match_render_<kind>
# claims $target. text.sh is today's real body (the old inline
# lesskey/bat/`exec less` tail, moved in verbatim); fallback.sh is the
# always-0 catch-all. Most renderers `exec`, so this call does not return.
render_any "$target" "$CLIP_LINE"
exit $?
