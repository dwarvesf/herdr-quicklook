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
case "$(classify_token "$raw")" in
  github)
    if map_github_url "$raw" && target="$(resolve_github "$GH_REPO" "$GH_REST")"; then
      CLIP_LINE="$GH_LINE"
    else
      # no local checkout matches: the browser is the right place after all
      url_open "$raw"
      exit 0
    fi
    ;;
  url)
    url_open "$raw"
    exit 0
    ;;
  path)
    parse_token "$raw"
    target="$(resolve "$CLIP_PATH")" || true
    ;;
esac

if [ -z "${target:-}" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$root" ]; then
    matches="$(git -C "$root" ls-files 2>/dev/null | grep -iF -- "$CLIP_PATH" | head -100)"
    n="$(printf '%s' "$matches" | grep -c . 2>/dev/null)"
    if [ "$n" -eq 1 ]; then
      target="$root/$matches"
    elif [ "$n" -gt 1 ]; then
      if command -v fzf >/dev/null 2>&1; then
        pick="$(printf '%s\n' "$matches" | fzf --prompt="$CLIP_PATH ▸ " --reverse --cycle --height=100%)" || exit 0
        [ -n "$pick" ] && target="$root/$pick"
      else
        # no fzf: list the candidates so the user can copy an exact path and retry
        printf '%s matches "%s" in this repo (install fzf for an interactive pick):\n\n' "$n" "$CLIP_PATH"
        printf '%s\n' "$matches"
        printf '\n'
        read -r -n1 -p "press any key to close" _ 2>/dev/null || sleep 2
        exit 0
      fi
    fi
  fi
fi

[ -z "${target:-}" ] && pause_close "quicklook: not a file I can find: $raw" \
  "(tried as-is, \$PWD, this repo's worktrees, QUICKLOOK_ROOTS, repo filename search)"

# Render with less driving the real FILE (not a bat pipe), so less keeps the
# filename and its `visual` command works: `o` (or `v`) escalates to the
# herdr-file-viewer pane via scripts/escalate.sh. bat becomes the LESSOPEN
# preprocessor for syntax highlighting; without bat, plain less -N.
lesskey_args=()
[ -f "$script_dir/../lesskey" ] && lesskey_args=(--lesskey-src="$script_dir/../lesskey")

export VISUAL="$script_dir/escalate.sh"
# Read by the lesskey `e` pshell binding (escalate-editor.sh); see lesskey.
export QUICKLOOK_EDITOR_SCRIPT="$script_dir/escalate-editor.sh"
if command -v bat >/dev/null 2>&1; then
  export LESSOPEN='|bat --color=always --style=numbers,header %s'
  exec less -R "${lesskey_args[@]}" ${CLIP_LINE:++$CLIP_LINE} "$target"
fi
exec less -N "${lesskey_args[@]}" ${CLIP_LINE:++$CLIP_LINE} "$target"
