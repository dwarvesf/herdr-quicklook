# shellcheck shell=bash
# lib.sh, shared helpers for herdr-quicklook scripts (sourced, keeps .sh).
# shellcheck disable=SC2034  # CLIP_PATH/CLIP_LINE are consumed by the sourcing scripts

herdr_bin="${HERDR_BIN_PATH:-herdr}"

clip_read() {
  if command -v pbpaste >/dev/null 2>&1; then pbpaste
  elif command -v wl-paste >/dev/null 2>&1; then wl-paste --no-newline
  elif command -v xclip >/dev/null 2>&1; then xclip -o -selection clipboard
  fi 2>/dev/null | head -1 | xargs
}

url_open() {
  if command -v open >/dev/null 2>&1; then open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1"
  fi >/dev/null 2>&1
}

# Optional config: QUICKLOOK_ROOTS, colon-separated extra roots to try for
# relative paths (e.g. the parent directory holding all your repos).
load_config() {
  local dir
  dir="$("$herdr_bin" plugin config-dir herdr-quicklook 2>/dev/null)"
  # shellcheck disable=SC1091
  [ -n "$dir" ] && [ -f "$dir/.env" ] && . "$dir/.env"
}

# pick_token [arg] -> the token to open, priority: $QUICKLOOK_TOKEN env (the
# only channel that crosses `herdr plugin pane open --env`) > first argument
# (natural CLI/agent shape) > clipboard (interactive default). Empty env = unset.
pick_token() {
  local t="${QUICKLOOK_TOKEN:-}"
  [ -z "$t" ] && t="${1:-}"
  [ -z "$t" ] && t="$(clip_read)"
  printf '%s' "$t"
}

# split "path:123" into CLIP_PATH / CLIP_LINE
parse_token() {
  CLIP_PATH="$1"
  CLIP_LINE=""
  if [[ "$1" =~ ^(.+):([0-9]+)$ ]]; then
    CLIP_PATH="${BASH_REMATCH[1]}"
    CLIP_LINE="${BASH_REMATCH[2]}"
  fi
}

# resolve <path> -> ABSOLUTE file path on stdout, or rc 1.
# Order: as-is, $PWD, every worktree of the current repo, each QUICKLOOK_ROOTS.
# Always absolute: a downstream containment check ("is it under the repo root")
# must compare against absolute roots, so a bare relative hit is joined to $PWD.
resolve() {
  local p="$1" w r
  if [ -f "$p" ]; then
    case "$p" in
      /*) printf '%s' "$p" ;;
      *) printf '%s' "$PWD/$p" ;;
    esac
    return 0
  fi
  [ -f "$PWD/$p" ] && { printf '%s' "$PWD/$p"; return 0; }
  while IFS= read -r w; do
    [ -f "$w/$p" ] && { printf '%s' "$w/$p"; return 0; }
  done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
  local IFS=':'
  for r in ${QUICKLOOK_ROOTS:-}; do
    [ -n "$r" ] && [ -f "$r/$p" ] && { printf '%s' "$r/$p"; return 0; }
  done
  return 1
}
