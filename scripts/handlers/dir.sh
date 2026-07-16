# shellcheck shell=bash
# dir.sh: a token that resolves to a DIRECTORY (not a file) opens the
# herdr-file-viewer rooted there when that plugin is installed (render-mode
# `viewer`), else pages an `eza --tree` (fallback `ls -la`) listing in the
# popup (render-mode `command`). Registered ahead of path.sh's catch-all in
# HANDLER_KINDS (see lib.sh) - `_resolve_dir` below must never shadow a real
# file: it walks the SAME candidate order path.sh's own resolve() uses (as-is,
# $PWD, every worktree, each QUICKLOOK_ROOTS) and tests -f before -d at every
# step, declining the whole search the instant a FILE wins a step, so a
# directory hit at a LATER root can never jump ahead of an EARLIER root's file.
# shellcheck disable=SC2034  # RESOLVED_* are consumed by the caller (resolve_any_token's caller)

# _dir_candidates <raw> -> one ABSOLUTE candidate path per line, in the same
# effective priority order path.sh's own resolve() walks (as-is/$PWD, every
# worktree, each QUICKLOOK_ROOTS). Always absolute so a downstream
# containment check (open-in-viewer.sh: "is target under the repo root")
# compares against an absolute root, same reason resolve() itself absolutizes.
_dir_candidates() {
  local p="$1" w r
  case "$p" in
    /*) printf '%s\n' "$p" ;;
    *) printf '%s\n' "$PWD/$p" ;;
  esac
  while IFS= read -r w; do
    printf '%s\n' "$w/$p"
  done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
  local IFS=':'
  for r in ${QUICKLOOK_ROOTS:-}; do
    [ -n "$r" ] && printf '%s\n' "$r/$p"
  done
}

# _resolve_dir <raw> -> absolute directory path on stdout, rc 0. rc 1 when no
# candidate is a directory, OR when an earlier-priority candidate is a
# regular file instead (that file always wins its step - see header comment).
_resolve_dir() {
  local raw="$1" cand
  while IFS= read -r cand; do
    [ -f "$cand" ] && return 1
    [ -d "$cand" ] && { printf '%s' "$cand"; return 0; }
  done < <(_dir_candidates "$raw")
  return 1
}

# _dir_viewer_available -> rc 0 if herdr-file-viewer is installed, the same
# check open-in-viewer.sh's own soft-dependency gate uses.
# shellcheck disable=SC2154  # herdr_bin is set by lib.sh before this file is sourced
_dir_viewer_available() {
  "$herdr_bin" plugin action list --plugin herdr-file-viewer >/dev/null 2>&1
}

match_dir() {
  _resolve_dir "$1" >/dev/null
}

handle_dir() {
  local dir
  dir="$(_resolve_dir "$1")" || return 1
  RESOLVED_TARGET="$dir"
  RESOLVED_LINE=""
  if _dir_viewer_available; then
    RESOLVED_MODE="viewer"
    return 0
  fi
  RESOLVED_MODE="command"
  if command -v eza >/dev/null 2>&1; then
    RESOLVED_CMD=(eza --tree "$dir")
  else
    RESOLVED_CMD=(ls -la "$dir")
  fi
  return 0
}
