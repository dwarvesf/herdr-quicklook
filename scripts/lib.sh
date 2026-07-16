# shellcheck shell=bash
# lib.sh, shared helpers for herdr-quicklook scripts (sourced, keeps .sh).
# shellcheck disable=SC2034  # CLIP_PATH/CLIP_LINE are consumed by the sourcing scripts

# -----------------------------------------------------------------------
# Handler-registry contract
#
# A token kind lives in its own scripts/handlers/<kind>.sh and exports two
# functions:
#
#   match_<kind> <raw>   -> rc 0 if this handler owns the token's shape. No
#                           resolution work, no side effects.
#   handle_<kind> <raw>  -> resolves the token. On success sets
#                           RESOLVED_TARGET / RESOLVED_LINE / RESOLVED_MODE
#                           (and RESOLVED_CMD for `command` mode, see below)
#                           and returns 0. A handler that recognizes the
#                           token's shape but cannot resolve a target returns
#                           1; the caller decides what happens next
#                           (open-in-viewer.sh reports "not found";
#                           preview-pane.sh additionally tries the bare-name
#                           fuzzy fallback below).
#
# RESOLVED_MODE is one of, and BOTH pane scripts act on all four (see their
# own RESOLVED_MODE case block; this is load-bearing, not aspirational , a
# handler is free to emit any of these today and get correct behavior):
#   file    - RESOLVED_TARGET is a local path (RESOLVED_LINE optional);
#             caller renders/drives it. Produced today by github.sh, path.sh.
#   browser - RESOLVED_TARGET is a URL; caller does
#             `url_open "$RESOLVED_TARGET"`. Produced today by github.sh
#             (no local checkout), url.sh.
#   command - RESOLVED_CMD (a bash ARRAY, not a string) is the argv to run;
#             its output is paged for the user. A flat string is not enough
#             here: a command-mode handler runs an external tool (`git show`,
#             `gh pr view`) against untrusted clipboard input, so the args
#             must stay a real argv and never get rebuilt from a flattened
#             string (that would reopen the exact shell-injection surface
#             the mode exists to avoid). Widened per this sub-goal's own
#             contingency clause; see DECISIONS.md. preview-pane.sh runs
#             RESOLVED_CMD through render_command_in_pager (below) directly
#             (it has the real TTY); open-in-viewer.sh has no pager of its
#             own, so it re-invokes the SAME raw token through
#             scripts/open-preview.sh (a fresh resolve_any_token call there
#             reproduces the identical RESOLVED_CMD deterministically , safe
#             for command-mode specifically, see the viewer caveat below).
#             No handler emits this yet (SG-02/vcs.sh is a stub).
#   viewer  - RESOLVED_TARGET is a directory to root the file-viewer at.
#             preview-pane.sh's safe DEGRADE (no handler drives the real
#             file-viewer socket protocol yet) pages an `eza --tree` /
#             `ls -la` listing of RESOLVED_TARGET via render_command_in_pager
#             , the same shape SG-04's own goal file already documents as
#             its no-viewer-installed fallback. open-in-viewer.sh cannot do
#             even that (no pager of its own) and cannot safely forward the
#             raw token the way command-mode does either: path.sh's
#             resolve() only matches regular files (`-f`), so a directory
#             token would fail to re-resolve there and silently read as "not
#             found". It notifies the user and stops instead. Neither arm
#             ever falls through to file-rendering on a directory ,
#             the concrete bug this widening exists to prevent. Real
#             viewer-rooting over the herdr socket is SG-04's own feature;
#             expect it to replace these degrade bodies. No handler emits
#             this yet (SG-04/dir.sh is a stub).
#
# resolve_any_token <raw> walks HANDLER_KINDS in order and dispatches to the
# first handler whose match_<kind> accepts the token, returning that
# handler's rc. Order matters: `path` (scripts/handlers/path.sh) is the
# catch-all (match_path always succeeds), so it MUST stay last, or a
# later-added kind's real tokens would never reach their own handler.
#
# scripts/preview-pane.sh and scripts/open-in-viewer.sh call ONLY
# resolve_any_token to CLASSIFY/RESOLVE a token; that side is never edited to
# add a new kind. Each script's own RESOLVED_MODE case block is where the
# four modes above render/act; a kind whose handler starts emitting `viewer`
# or `command` for real (SG-02/SG-04) is expected to refine those bodies ,
# a disclosed, minor exception to "pane scripts untouched", see HANDOFF.md.
# Adding a purely additive kind (mode file/browser only) needs zero
# pane-script edits: one new scripts/handlers/<kind>.sh + one line in
# HANDLER_KINDS below.
#
# scripts/handlers/bare-name.sh is the one documented exception: its fuzzy
# git-ls-files search + interactive fzf pick is opt-in (match_bare_name
# always declines automatic dispatch); preview-pane.sh calls
# handle_bare_name directly when resolve_any_token reports no match.
# open-in-viewer.sh intentionally does not, so its behavior is unchanged
# from before this refactor. See DECISIONS.md.
# -----------------------------------------------------------------------

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

# record_open <token> -> no-op today (best-effort). SG-07 (recents) fills in
# the body; both pane scripts already call this at the point a successful
# open is known, so that sub-goal stays a lib.sh-only change for the body
# itself (it may still touch the pane scripts' call sites, see DECISIONS.md).
record_open() { :; }

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

# classify_token <raw> -> github | url | path
classify_token() {
  case "$1" in
    https://github.com/*/blob/* | https://github.com/*/raw/* | https://raw.githubusercontent.com/*)
      printf 'github' ;;
    http://* | https://*) printf 'url' ;;
    *) printf 'path' ;;
  esac
}

# decode %XX url-escapes only (GitHub blob paths can carry %20 etc.). A literal
# '+' in a URL PATH is a plus, not a space (that is query-string decoding), so it
# is left alone. Backslashes in the input are escaped first so printf '%b' cannot
# interpret attacker-supplied \n / \x sequences that were never %-encoded.
urldecode() {
  local s="${1//\\/\\\\}"
  printf '%b' "${s//\%/\\x}"
}

# map_github_url <url>: extract GH_REPO, GH_REST (ref/path, decoded), GH_LINE.
# Accepted shapes: github.com/<o>/<r>/blob/<ref>/<path>[#L<n>[-L<m>]],
# github.com/<o>/<r>/raw/<ref>/<path>, raw.githubusercontent.com/<o>/<r>/<ref>/<path>.
# A #L<n>-L<m> range keeps the start line.
map_github_url() {
  GH_REPO=""
  GH_REST=""
  GH_LINE=""
  local u="$1" frag="" rest=""
  case "$u" in
    *'#L'*)
      frag="${u##*#L}"
      u="${u%%#*}"
      ;;
  esac
  u="${u%%\?*}" # drop any ?query (e.g. GitHub's ?plain=1) before splitting
  if [[ "$frag" =~ ^([0-9]+) ]]; then GH_LINE="${BASH_REMATCH[1]}"; fi
  case "$u" in
    https://github.com/*/blob/*)
      rest="${u#https://github.com/}"
      GH_REPO="$(printf '%s' "$rest" | cut -d/ -f2)"
      GH_REST="${rest#*/*/blob/}"
      ;;
    https://github.com/*/raw/*)
      rest="${u#https://github.com/}"
      GH_REPO="$(printf '%s' "$rest" | cut -d/ -f2)"
      GH_REST="${rest#*/*/raw/}"
      ;;
    https://raw.githubusercontent.com/*)
      rest="${u#https://raw.githubusercontent.com/}"
      GH_REPO="$(printf '%s' "$rest" | cut -d/ -f2)"
      GH_REST="${rest#*/*/}"
      ;;
    *) return 1 ;;
  esac
  GH_REST="$(urldecode "$GH_REST")"
  [ -n "$GH_REPO" ] && [ -n "$GH_REST" ]
}

# unsafe_relpath <candidate> -> rc 0 if the candidate is absolute or carries a
# `..` traversal segment. A GitHub URL path is always repo-relative, so an
# absolute or traversal candidate is a smuggled path (e.g.
# `blob/main//etc/passwd`, `blob/main/../../etc/passwd`) and must be refused;
# without this, resolve()'s literal `-f` test would open the smuggled file.
unsafe_relpath() {
  case "$1" in
    /* | ../* | */../* | */.. | ..) return 0 ;;
    *) return 1 ;;
  esac
}

# resolve_github <repo> <ref/path> -> local absolute path on stdout, or rc 1.
# The ref may contain '/', so try successive splits (drop 1..4 leading
# segments) against: the current repo when its directory name matches <repo>,
# the plain resolve chain, and each QUICKLOOK_ROOTS/<repo>. Caller falls back
# to the browser on rc 1.
resolve_github() {
  local repo="$1" rest="$2" i cand root gname r
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  gname="${root##*/}"
  for i in 2 3 4 5; do
    cand="$(printf '%s' "$rest" | cut -d/ -f"$i"-)"
    [ -z "$cand" ] && break
    unsafe_relpath "$cand" && continue
    if [ -n "$root" ] && [ "$gname" = "$repo" ] && [ -f "$root/$cand" ]; then
      printf '%s' "$root/$cand"
      return 0
    fi
    if resolve "$cand"; then return 0; fi
    local IFS=':'
    for r in ${QUICKLOOK_ROOTS:-}; do
      [ -n "$r" ] && [ -f "$r/$repo/$cand" ] && { printf '%s' "$r/$repo/$cand"; return 0; }
    done
    unset IFS
  done
  return 1
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

# Registry order (first match wins): specific-shape kinds before the
# catch-all. `path` MUST stay last (see the contract comment at the top of
# this file). vcs/dir are registered now as stubs (SG-02/SG-04 fill in their
# match_/handle_ bodies later, one file each, no registry-line edit needed).
HANDLER_KINDS=(github url vcs dir path)

# LIB_DIR: this file's own directory (== scripts/), kept around (not
# unset) so render_command_in_pager below can find ../lesskey the same way
# the pane scripts locate it from their own script_dir.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _herdr_handler in "$LIB_DIR"/handlers/*.sh; do
  # shellcheck disable=SC1090
  [ -f "$_herdr_handler" ] && . "$_herdr_handler"
done
unset _herdr_handler

# render_command_in_pager <argv...> -> runs argv, pages its combined
# stdout+stderr through less (color preserved via -R, so a command that
# emits ANSI itself, e.g. `git show --color=always`, still highlights).
# Used for RESOLVED_MODE=command and preview-pane.sh's RESOLVED_MODE=viewer
# tree-listing degrade (see the contract comment above). Only meaningful
# from a script with a real TTY (preview-pane.sh); returns the pipeline's
# exit status.
render_command_in_pager() {
  local lesskey_args=()
  [ -f "$LIB_DIR/../lesskey" ] && lesskey_args=(--lesskey-src="$LIB_DIR/../lesskey")
  "$@" 2>&1 | less -R "${lesskey_args[@]}"
}

# resolve_any_token <raw> -> see the handler-registry contract at the top of
# this file. Sets RESOLVED_TARGET / RESOLVED_LINE / RESOLVED_MODE (and
# RESOLVED_CMD for command mode) and returns 0 on a resolved token, or
# returns 1 if no handler matched, or the matched handler could not resolve
# a target (caller does its own fallback, if any).
resolve_any_token() {
  local raw="$1" kind
  RESOLVED_TARGET=""
  RESOLVED_LINE=""
  RESOLVED_MODE=""
  RESOLVED_CMD=()
  for kind in "${HANDLER_KINDS[@]}"; do
    if "match_$kind" "$raw"; then
      "handle_$kind" "$raw"
      return $?
    fi
  done
  return 1
}
