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
#             Produced today by vcs.sh (SG-02: bare SHA -> `git show`, `#123`
#             / PR URL -> `gh pr view`) and dir.sh (SG-04: herdr-file-viewer
#             absent -> `eza --tree`/`ls -la`).
#   viewer  - RESOLVED_TARGET is a directory to root the file-viewer at.
#             dir.sh only emits this mode when herdr-file-viewer is
#             confirmed installed (else it emits `command` with an
#             eza/ls tree instead, see below). preview-pane.sh (the popup)
#             still cannot drive ANOTHER pane's file-viewer socket - it has
#             only its own TTY, a pager - so its viewer arm is a permanent
#             safe DEGRADE, paging an `eza --tree` / `ls -la` listing of
#             RESOLVED_TARGET via render_command_in_pager, the same shape as
#             dir.sh's own no-viewer-installed fallback. open-in-viewer.sh
#             CAN drive another pane, so its viewer arm reuses the same
#             goto-path send-keys sequence the file case already uses (f ->
#             type <repo-relative path> -> Enter) to land the viewer's
#             cursor on the directory. Neither arm ever falls through to
#             file-rendering on a directory , the concrete bug this
#             widening exists to prevent.
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

# ---- recents (SG-07): a small "last opened" log, read by the `recents`
# action / recents-pick pane (scripts/recents.sh, scripts/recents-pane.sh).
# State lives under a proper state dir, NEVER inside a repo working tree,
# see recents_path_is_safe below.

# RECENTS_MAX: bounded log size (last-N, deduped). Overridable for tests.
RECENTS_MAX="${QUICKLOOK_RECENTS_MAX:-20}"

# recents_state_dir -> the directory the recents log lives in (not created
# here). ${XDG_STATE_HOME:-$HOME/.local/state}/herdr-quicklook, per this
# sub-goal's goal file. Not the plugin config-dir: that would mean shelling
# out to `herdr plugin config-dir` (an extra process, and a hard runtime
# dependency on herdr itself) on every single successful open, when the XDG
# state dir needs nothing more than $HOME.
recents_state_dir() {
  printf '%s/herdr-quicklook' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# recents_state_file -> the recents log itself.
recents_state_file() {
  printf '%s/recents' "$(recents_state_dir)"
}

# recents_path_is_safe <path> -> rc 0 if no ancestor directory of <path> is
# a git working tree (a `.git` entry - a directory for a normal repo, a file
# for a worktree/submodule gitlink). A pure path-walk, no `git` binary
# required and no dependency on the directory existing yet, so it works
# before the first `mkdir -p`. This is the hard guard the goal file
# requires: state must NEVER land inside a repo, however
# XDG_STATE_HOME/$HOME ends up set on a given machine.
recents_path_is_safe() {
  local d
  d="$(dirname -- "$1")"
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    [ -e "$d/.git" ] && return 1
    d="$(dirname -- "$d")"
  done
  return 0
}

# record_open <token> -> append <token> to the recents log: dedup (an
# existing occurrence of the same token moves to the front instead of
# duplicating) and cap at RECENTS_MAX (oldest entries drop off). Best-effort
# by design (this sub-goal's Quality bar): an empty token, an unsafe path,
# an unwritable dir, or any write failure is silently swallowed - a
# recording failure must never block the open it is recording. Atomic:
# builds the new content in a temp file in the SAME directory, then renames
# over the real file, so a concurrent reader never observes a half-written
# log.
record_open() {
  local token="$1" file dir tmp
  [ -z "$token" ] && return 0
  file="$(recents_state_file)"
  dir="$(dirname -- "$file")"
  recents_path_is_safe "$file" || return 0
  mkdir -p -- "$dir" 2>/dev/null || return 0
  tmp="$(mktemp "$dir/.recents.XXXXXX" 2>/dev/null)" || return 0
  if {
    [ -f "$file" ] && grep -Fxv -- "$token" "$file" 2>/dev/null
    printf '%s\n' "$token"
  } | tail -n "$RECENTS_MAX" >"$tmp" 2>/dev/null; then
    mv -f -- "$tmp" "$file" 2>/dev/null
  else
    rm -f -- "$tmp" 2>/dev/null
  fi
  return 0
}

# recents_list -> the recents log, MOST-RECENT-FIRST, one token per line.
# Missing or empty file: no output, rc 0. A corrupt/unreadable file never
# crashes the caller (errors are swallowed; worst case is fewer or garbled
# candidates, never a nonzero exit the caller has to guard against).
recents_list() {
  local file
  file="$(recents_state_file)"
  [ -f "$file" ] || return 0
  # Reverse without depending on GNU-only `tac` (not on macOS by default);
  # this sed idiom is portable to BSD sed too.
  sed '1!G;h;$!d' "$file" 2>/dev/null
  return 0
}

# recents_latest -> the single most-recently-opened token, or empty.
recents_latest() {
  recents_list | head -1
}

# Optional config: QUICKLOOK_ROOTS, colon-separated extra roots to try for
# relative paths (e.g. the parent directory holding all your repos).
load_config() {
  local dir="${HERDR_PLUGIN_CONFIG_DIR:-}"
  [ -n "$dir" ] || dir="$("$herdr_bin" plugin config-dir herdr-quicklook 2>/dev/null)"
  # shellcheck disable=SC1091
  [ -n "$dir" ] && [ -f "$dir/.env" ] && . "$dir/.env"
}

# Single-char hint keys for the native `hint` overlay, home-row first so the
# most-relevant tokens (rendered top-down) get the easiest keys. `q` is
# excluded: it is the cancel key, so a token labeled q could never be picked.
# 25 keys is the ceiling; a busier pane shows only the first 25 (ranked).
# ponytail: 25-cap, add two-char hints only if a real pane ever overflows.
QUICKLOOK_HINT_KEYS="asdfghjklwertyuiopzxcvbnm"

# hint_key_for_index <0-based-index> -> the hint char, rc 1 if out of range.
hint_key_for_index() {
  local i="$1"
  case "$i" in *[!0-9]*|'') return 1 ;; esac
  [ "$i" -lt "${#QUICKLOOK_HINT_KEYS}" ] || return 1
  printf '%s' "${QUICKLOOK_HINT_KEYS:$i:1}"
}

# hint_index_for_key <char> -> the 0-based index, rc 1 if not a hint key.
hint_index_for_key() {
  local k="$1" i=0
  [ -n "$k" ] || return 1
  while [ "$i" -lt "${#QUICKLOOK_HINT_KEYS}" ]; do
    [ "${QUICKLOOK_HINT_KEYS:$i:1}" = "$k" ] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
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

QUICKLOOK_LINK_PREFIX='https://herdr-quicklook.invalid/open?token='

quicklook_link_uri() {
  local token="${1:-}" encoded
  [ -n "$token" ] || return 1
  [[ "$token" =~ [[:cntrl:]] ]] && return 1
  command -v jq >/dev/null 2>&1 || return 1
  encoded="$(jq -rn --arg token "$token" '$token | @uri')" || return 1
  [ -n "$encoded" ] || return 1
  printf '%s%s' "$QUICKLOOK_LINK_PREFIX" "$encoded"
}

quicklook_token_from_link() {
  local uri="${1:-}" encoded token canonical
  case "$uri" in
    "$QUICKLOOK_LINK_PREFIX"*) encoded="${uri#"$QUICKLOOK_LINK_PREFIX"}" ;;
    *) return 1 ;;
  esac
  [ -n "$encoded" ] || return 1
  case "$encoded" in
    *'&'* | *'#'*) return 1 ;;
  esac
  token="$(urldecode "$encoded")" || return 1
  [ -n "$token" ] || return 1
  [[ "$token" =~ [[:cntrl:]] ]] && return 1
  canonical="$(quicklook_link_uri "$token")" || return 1
  [ "$canonical" = "$uri" ] || return 1
  printf '%s' "$token"
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
# this file). `vcs` sits BEFORE `url` (not after, as originally stubbed):
# one of vcs's shapes is a GitHub PR URL (https://...), which structurally
# also matches url.sh's generic http(s) predicate via classify_token; if url
# stayed first it would claim every PR URL as a generic browser-mode open
# before vcs ever got a look. vcs's other two shapes (bare SHA, `#123`)
# don't overlap anything, so this reorder is a no-op for them. `dir` is real
# too (SG-04): it decides viewer vs command mode itself, see the contract
# comment above.
HANDLER_KINDS=(github vcs url dir path)

# LIB_DIR: this file's own directory (== scripts/), kept around (not
# unset) so render_command_in_pager below can find ../lesskey the same way
# the pane scripts locate it from their own script_dir.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# herdr's server-spawned panes carry no login env, so less falls back to a
# non-UTF-8 charset and prints multibyte characters as raw bytes (<E2><86><92>
# for a plain arrow). Force UTF-8 for every pager/render path that sources
# this file; an explicit user locale still wins.
export LESSCHARSET="${LESSCHARSET:-utf-8}"
[ -n "${LANG:-}" ] || export LANG=en_US.UTF-8
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

# -----------------------------------------------------------------------
# pick-anywhere scan (v0.5, SG-01): pick_scan_text / pick_count_header /
# pick_acquire, plus the action/pane wiring contract Wave 2 (SG-02, SG-03)
# builds against.
#
# pick_scan_text (pure core, the whole serializer): reads pane TEXT on
# stdin, emits the ranked, deduped candidate list on stdout, one candidate
# per line, TAB-delimited:
#   <raw-token>\t<kind>\t<line-no>
# <kind> is one of path url sha ref dir name (sha+ref are the two vcs
# shapes, kept distinct only for pick_count_header's count-by-kind
# header).
#
# Classification REUSES the handler registry above - never a new regex
# zoo - for every CHEAP, subprocess-free shape check (match_github,
# match_vcs, match_url, match_path's classify_token, and the pure URL
# mappers map_github_url/map_gitlab_url/map_bitbucket_url). The kind is
# keyed on which handler claims the span (walking the SAME live
# HANDLER_KINDS array resolve_any_token uses, not a hardcoded copy):
#   github -> resolves to a local file  -> path
#   github -> no local checkout         -> url  (same bucket as any
#                                                 generic URL - github.sh's
#                                                 own handle_github never
#                                                 treats this as a miss)
#   vcs    -> shape matches _VCS_SHA_RE (vcs.sh's own pattern, reused
#             directly, not re-derived)               -> sha
#   vcs    -> otherwise (a #ref or a PR URL, both dispatch to `gh pr
#             view`)                                  -> ref
#   url    -> (always)                                -> url
#   dir    -> resolves to a real directory              -> dir
#   path   -> resolves to a real file                   -> path
#   path   -> unresolved, but a UNIQUE bare-name hit (the same
#             case-insensitive substring rule bare-name.sh uses)
#                                                        -> name
#   anything else                                       -> dropped, not
#                                                          a candidate
# match_path always returns 0 (the catch-all - see the contract at the
# top of this file), so `path` as a KIND is asserted by RESOLUTION
# success, never by match_path alone.
#
# PERFORMANCE (fixed post-review, see DECISIONS.md "SG-01 CRITICAL fix"):
# the FIRST implementation classified every raw OCCURRENCE of every span,
# and each dir/path/name check forked its own `git worktree list`/`git
# rev-parse`/`git ls-files` - O(spans x subprocesses), measured 13.5s on a
# normal 40x15 screen and 1m54s on 500 lines. Fixed two ways:
#   1. Spans are DEDUPED FIRST (one awk pass over the whole screen: tokenize
#      + trim + dedup, keeping the bottom-most line-no per unique span),
#      THEN each UNIQUE span is classified exactly once - classification
#      cost no longer scales with repeat occurrences.
#   2. Every dir/path/github/name check that would otherwise fork `git` is
#      answered by a SCAN-LOCAL PURE PREDICATE (_pick_resolve_local,
#      _pick_resolve_dir_local, _pick_resolve_github_local,
#      _pick_bare_name_hit_local) built against THREE pieces of repo state
#      hoisted ONCE PER SCAN, not once per span: `git rev-parse
#      --show-toplevel`, `git worktree list --porcelain`, `git ls-files`.
#      These predicates mirror resolve()/`_resolve_dir()`/resolve_github()
#      exactly, just reading the hoisted data instead of re-invoking git;
#      the shipped handlers (handle_path/handle_dir/handle_github/
#      handle_bare_name) are still what OPENING a token runs through
#      (preview-pane.sh, unchanged) - only the SCAN's own classification
#      pass uses the hoisted-data versions, and it documents the pairing
#      right where each predicate is defined below. A useful side effect:
#      since the scan no longer calls handle_path/handle_dir/handle_github
#      /handle_bare_name at all, it never touches RESOLVED_TARGET/
#      RESOLVED_LINE/RESOLVED_MODE/RESOLVED_CMD/CLIP_PATH/CLIP_LINE either
#      - see the purity note below.
#
# BASH 3.2 REWRITE (gate review, superseding the bash>=4.3 guard): the
# tokenize/trim/dedup pass and the final rank/sort used to lean on bash 4.3
# `local -n` namerefs (to avoid forking a subshell per span) and bash 4.0
# `local -A` associative arrays (for the dedup/kind maps) - unavailable on
# macOS's own `/bin/bash` (3.2, last GPLv2 release). Rewritten to keep the
# SAME zero-fork-per-span property on any bash >= 3.2:
#   - Tokenize + trim + dedup is now ONE awk process (a single pass over
#     the whole screen, not a bash loop calling a nameref-based helper once
#     per raw span) - see Pass 1 in pick_scan_text below.
#   - Classification still runs once per UNIQUE span in bash (the
#     filesystem-aware predicates above need it), but _pick_classify_span
#     now writes its result to a fixed-name global (_PICK_CLASSIFY_KIND)
#     instead of a caller-supplied `local -n` outvar - a plain function
#     call, no subshell, no nameref, and it has exactly one caller so a
#     fixed output variable costs nothing.
#   - The final tier/sort ranking is an awk + `sort` + awk pipeline instead
#     of a bash `local -A` map and a bash `printf`-per-token sort-key loop.
#   Net effect: no bash-version guard needed any more - hint-era panes no
#   longer checks $BASH_VERSINFO before calling pick_acquire. See
#   DECISIONS.md (ops-toolkit) for the measured before/after on both a
#   modern bash and macOS's real bash 3.2.
#
# PURITY: pick_scan_text never mutates a global. It does not call
# parse_token, handle_path, handle_dir, handle_github, handle_vcs, or
# handle_bare_name, so none of CLIP_PATH/CLIP_LINE/RESOLVED_TARGET/
# RESOLVED_LINE/RESOLVED_MODE/RESOLVED_CMD are touched by a scan - a
# caller's own in-flight state (e.g. mid-resolve in another script) is
# never clobbered by scanning. (GH_REPO/GH_REST/GH_LINE ARE still set as a
# side effect of calling map_github_url/map_gitlab_url/map_bitbucket_url -
# the SAME pre-existing globals github.sh's own handle_github already
# sets on every normal github-URL open, not a new leak this scan
# introduces.)
#
# ANSI/OSC DEFENSE: the whole screen is passed through _pick_strip_ansi
# ONCE (a single sed pass, not per line/span) before tokenizing, stripping
# CSI (`ESC [ ... letter`, e.g. SGR color codes) and OSC (`ESC ] ... BEL`,
# e.g. terminal title sequences) escape sequences. Live-verified
# 2026-07-17 against a real herdr pane (`herdr pane run` printed raw ANSI
# color codes, then `herdr pane read --format text` vs `--format ansi`
# were diffed byte-for-byte): `--format text` - what pick_acquire already
# requests - ALREADY strips every escape sequence before pick_scan_text
# ever sees the text. So this strip is a defensive no-op on the
# pick_acquire path specifically, but it protects any OTHER caller that
# pipes raw/ANSI-decorated text into pick_scan_text directly (a bats
# fixture, a future integration) - see DECISIONS.md for the full finding.
#
# Dedup: the SAME raw token seen more than once keeps only the occurrence
# CLOSEST TO THE BOTTOM (the largest line-no) - a plain top-to-bottom walk
# that overwrites its dedup-map entry on every repeat gets this right
# with no extra bookkeeping.
#
# Rank: confidence tier, highest first - path (resolves to a real file) >
# url > sha > ref > dir > name. Tiebreak WITHIN a tier: larger line-no
# first (closer to the bottom = the most recent output); a THIRD tiebreak,
# the raw token itself (lexicographic ascending), makes the final order
# fully deterministic when two different tokens of the same kind land on
# the exact same line (no more relying on bash associative-array
# iteration order for that case).
#
# pick_count_header: given pick_scan_text's stdout on stdin, emits the
# one-line affordance `N on screen · A path · B url · C sha · D ref · E
# dir · F name`, listing only the non-zero kinds in that fixed order,
# N = total candidates.
#
# pick_acquire [pane_id]: the ONE live-dependency wrapper. Runs
# `"$herdr_bin" pane read "$pane_id" --source "${QUICKLOOK_PICK_SOURCE:-
# visible}" --format text` and pipes the result into pick_scan_text.
# pane_id defaults to $QUICKLOOK_PICK_ORIGIN_PANE; empty -> best-effort
# `herdr pane current | jq -r '.result.pane.pane_id'`. This is the only
# function in this section that needs a stubbed herdr in bats - everything
# else is the pure core, fixture-text/fixture-file testable, no live pane.
#
# ---- The action/pane wiring contract (pinned for SG-02 / SG-03) ----
# Action id `hint` -> scripts/hint.sh (no TTY, mirrors scripts/recents.sh):
#   1. captures the origin pane id BEFORE opening the overlay
#      (`herdr pane current | jq -r '.result.pane.pane_id'` - once the
#      hint-pane overlay is focused, `pane current` returns the OVERLAY,
#      not the origin the user was in);
#   2. reads the clipboard token (clip_read) and runs the WHOLE
#      `pick_acquire` scan HERE (an RPC from inside a server-spawned
#      overlay pane deadlocks - see the hint.sh header), writing the
#      clipboard-first "raw<TAB>label" list to a temp file;
#   3. opens the `hint-pane` overlay, forwarding
#      `--env QUICKLOOK_HINT_TOKENS_FILE=<file>` +
#      `--env QUICKLOOK_HINT_CWD=<origin cwd>` (env, never --cwd: --cwd
#      breaks the pane's relative command resolution).
# Pane id `hint-pane` -> scripts/hint-pane.sh (real TTY, no RPC at all):
#   4. reads the prepared token list, renders one hint key per row, each
#      row also an OSC-8 sentinel link (Ctrl+click -> open-link handler);
#   5. a hint keypress -> `export QUICKLOOK_TOKEN=<raw>; exec bash
#      preview-pane.sh` in this same pane.
#      (the SAME open path recents-pane.sh already reuses - resolve +
#      render + record_open, zero new open code);
#   7. Esc -> close, nothing opened; zero candidates and no resolvable
#      clipboard -> an honest empty state, never a crash.
# Confidence-tier order + tiebreak: as above (path > url > sha > ref >
# dir > name; within a tier, larger line-no first, then raw-token
# lexicographic ascending).
# -----------------------------------------------------------------------

# _pick_strip_ansi -> reads stdin, writes stdout with every CSI (`ESC [
# ... letter`) and OSC (`ESC ] ... BEL`) escape sequence removed, in ONE
# sed pass over the whole screen (never per line/span - see the
# PERFORMANCE note above). Defensive: see the ANSI/OSC DEFENSE note above
# for the live-verified finding that herdr's own `--format text` already
# does this.
_pick_strip_ansi() {
  sed -E $'s/\x1b\\[[0-9;]*[a-zA-Z]//g; s/\x1b\\][^\x07]*\x07//g'
}

# _pick_cut_from_field <rest> <i> -> the same result as `cut -d/ -f<i>-`
# (fields i..end of a '/'-delimited string, rejoined by '/'), in pure bash
# - no subprocess. _pick_resolve_github_local tries up to 4 splits per
# span (mirroring resolve_github's own i=2..5 loop); forking `cut` per
# split per span would reintroduce the same per-span subprocess cost this
# whole section exists to eliminate.
_pick_cut_from_field() {
  local rest="$1" i="$2" start out j
  local -a parts=()
  IFS='/' read -ra parts <<<"$rest"
  start=$((i - 1))
  [ "$start" -ge "${#parts[@]}" ] && return 0
  out="${parts[$start]}"
  for ((j = start + 1; j < ${#parts[@]}; j++)); do
    out="$out/${parts[$j]}"
  done
  printf '%s' "$out"
}

# _pick_resolve_local <path> -> ABSOLUTE file path on stdout, rc 0/1. A
# subprocess-free mirror of resolve() (as-is, $PWD, every worktree, each
# QUICKLOOK_ROOTS) that reads this scan's HOISTED _PICK_WORKTREES array
# instead of re-running `git worktree list` - see pick_scan_text, which
# sets _PICK_WORKTREES once per scan and is the only intended caller (bash
# dynamic scoping makes it visible here without passing it explicitly).
_pick_resolve_local() {
  local p="$1" w r
  if [ -f "$p" ]; then
    case "$p" in
      /*) printf '%s' "$p" ;;
      *) printf '%s' "$PWD/$p" ;;
    esac
    return 0
  fi
  [ -f "$PWD/$p" ] && { printf '%s' "$PWD/$p"; return 0; }
  for w in "${_PICK_WORKTREES[@]}"; do
    [ -f "$w/$p" ] && { printf '%s' "$w/$p"; return 0; }
  done
  local IFS=':'
  for r in ${QUICKLOOK_ROOTS:-}; do
    [ -n "$r" ] && [ -f "$r/$p" ] && { printf '%s' "$r/$p"; return 0; }
  done
  return 1
}

# _pick_resolve_dir_local <path> -> ABSOLUTE directory path on stdout, rc
# 0/1. Subprocess-free mirror of `_resolve_dir()`/`_dir_candidates()`
# (dir.sh) over the same hoisted _PICK_WORKTREES - a FILE at an
# earlier-priority candidate still wins its step (never lets a
# later-priority directory hit shadow an earlier file), matching dir.sh's
# own priority rule exactly.
_pick_resolve_dir_local() {
  local p="$1" w r cand
  local -a cands=()
  case "$p" in
    /*) cands+=("$p") ;;
    *) cands+=("$PWD/$p") ;;
  esac
  for w in "${_PICK_WORKTREES[@]}"; do
    cands+=("$w/$p")
  done
  local IFS=':'
  for r in ${QUICKLOOK_ROOTS:-}; do
    [ -n "$r" ] && cands+=("$r/$p")
  done
  unset IFS
  for cand in "${cands[@]}"; do
    [ -f "$cand" ] && return 1
    [ -d "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}

# _pick_resolve_github_local <repo> <rest> -> ABSOLUTE file path on
# stdout, rc 0/1. Subprocess-free mirror of resolve_github() (lib.sh
# above): same i=2..5 split-and-retry loop, same unsafe_relpath guard
# (reused directly - it is already pure), but reads the hoisted
# _PICK_ROOT instead of a fresh `git rev-parse`, calls
# _pick_resolve_local instead of resolve(), and _pick_cut_from_field
# instead of forking `cut`.
_pick_resolve_github_local() {
  local repo="$1" rest="$2" i cand gname r
  gname="${_PICK_ROOT##*/}"
  for i in 2 3 4 5; do
    cand="$(_pick_cut_from_field "$rest" "$i")"
    [ -z "$cand" ] && break
    unsafe_relpath "$cand" && continue
    if [ -n "$_PICK_ROOT" ] && [ "$gname" = "$repo" ] && [ -f "$_PICK_ROOT/$cand" ]; then
      printf '%s' "$_PICK_ROOT/$cand"
      return 0
    fi
    if _pick_resolve_local "$cand"; then return 0; fi
    local IFS=':'
    for r in ${QUICKLOOK_ROOTS:-}; do
      [ -n "$r" ] && [ -f "$r/$repo/$cand" ] && { printf '%s' "$r/$repo/$cand"; return 0; }
    done
    unset IFS
  done
  return 1
}

# _pick_lower <str> -> writes the lowercased string into the fixed global
# _PICK_LOWER_RESULT. Bash 3.2 (macOS system bash) has no `${var,,}`
# case-conversion operator (bash 4.0+) - this is the fork-free replacement,
# an unrolled `${s//X/x}` pattern-substitution per letter (26 pure-bash
# substitutions, no subprocess). Only ever called on a single SPAN (short),
# never on the whole hoisted file list - see _pick_bare_name_hit_local,
# which lowercases that list ONCE with a single `tr` instead.
_pick_lower() {
  local s="$1"
  s="${s//A/a}"; s="${s//B/b}"; s="${s//C/c}"; s="${s//D/d}"; s="${s//E/e}"
  s="${s//F/f}"; s="${s//G/g}"; s="${s//H/h}"; s="${s//I/i}"; s="${s//J/j}"
  s="${s//K/k}"; s="${s//L/l}"; s="${s//M/m}"; s="${s//N/n}"; s="${s//O/o}"
  s="${s//P/p}"; s="${s//Q/q}"; s="${s//R/r}"; s="${s//S/s}"; s="${s//T/t}"
  s="${s//U/u}"; s="${s//V/v}"; s="${s//W/w}"; s="${s//X/x}"; s="${s//Y/y}"
  s="${s//Z/z}"
  _PICK_LOWER_RESULT="$s"
}

# _pick_bare_name_hit_local <clip_path> -> rc 0 iff <clip_path> is a
# UNIQUE case-insensitive substring match against this scan's HOISTED
# _PICK_LSFILES (one `git ls-files` invocation for the whole scan, not one
# per span - see pick_scan_text). Reuses bare-name.sh's own matching rule
# (case-insensitive fixed-string substring, unique-hit-only) but stops
# there - no fzf, no exit-the-calling-script branch. handle_bare_name is
# NOT called: it is interactive UI by design (see bare-name.sh's own
# header comment) and can `exit` the calling process outright on an
# unresolved multi-match, which a pure text-in/text-out scan must never
# risk.
#
# Pure bash, no `grep` fork: an earlier version ran `grep -icF` per call,
# which is a single subprocess per UNIQUE unresolved span - fine for a
# handful of bare-name candidates, but a 500-line screen has hundreds of
# unique non-path words that all fall through to here, and forking grep
# for each one alone cost ~5s (measured). Looping a `case` glob match over
# the hoisted file list in-process removed that fork entirely; an early
# return the instant a SECOND match is seen keeps the common "ambiguous"
# case cheap too. See DECISIONS.md "SG-01 CRITICAL fix, round 2".
#
# Case-folding: the ORIGINAL implementation lowercased every LINE of the
# file list INSIDE this loop (`${line,,}`, bash 4.0+) - once per unresolved
# span, i.e. O(files x unresolved-spans) lowering work even under a modern
# bash. Neither `${line,,}` (bash 4+) nor a per-line `tr` fork belongs on
# bash 3.2 or in a hot loop, so the file list is lowercased into
# _PICK_LSFILES_LOWER ONCE for the whole scan (pick_scan_text's hoist
# step, a single `tr` call) and this function only ever lowercases the
# short per-span needle (_pick_lower, no fork) - a net perf win on top of
# the bash 3.2 fix.
_pick_bare_name_hit_local() {
  local clip_path="$1" needle line n=0
  [ -n "$clip_path" ] || return 1
  [ -n "$_PICK_ROOT" ] || return 1
  _pick_lower "$clip_path"
  needle="$_PICK_LOWER_RESULT"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *"$needle"*)
        n=$((n + 1))
        [ "$n" -gt 1 ] && return 1
        ;;
    esac
  done <<<"$_PICK_LSFILES_LOWER"
  [ "$n" -eq 1 ]
}

# _pick_match_kind <hkind> <span> -> rc 0 iff handler kind <hkind> claims
# <span>. Identical to calling `match_$hkind` directly for every kind
# EXCEPT `dir`: the real match_dir (dir.sh) forks `git worktree list` on
# every call via `_resolve_dir`, so the WIN-CHECK itself would reintroduce
# a per-span subprocess even though the classify step already switched to
# _pick_resolve_dir_local - this routes dir's win-check through the same
# hoisted-data predicate. Every other kind's match_<kind> is already
# subprocess-free (classify_token/regex/case checks only), so those are
# called as-is - REUSING the real handler, not a parallel copy.
_pick_match_kind() {
  local hkind="$1" span="$2"
  case "$hkind" in
    dir)
      # Fast mode: the dir probe is filesystem work; decline the kind and let
      # the catch-all path shape claim the span (dir.sh resolves it at open).
      [ -n "${QUICKLOOK_SCAN_FAST:-}" ] && return 1
      _pick_resolve_dir_local "$span" >/dev/null
      ;;
    *) "match_$hkind" "$span" ;;
  esac
}

# _pick_classify_span <span> -> writes one of path url sha ref dir name
# into the fixed global _PICK_CLASSIFY_KIND, or clears it to empty (a
# dropped span) - see the contract comment above. Walks the LIVE
# HANDLER_KINDS array (via _pick_match_kind) to decide which handler wins,
# then resolves using the scan-local pure predicates above - never
# handle_path/handle_dir/handle_github/handle_bare_name, so no
# RESOLVED_*/CLIP_PATH/CLIP_LINE global is ever touched (see the PURITY
# note above). Relies on _PICK_ROOT/_PICK_WORKTREES/_PICK_LSFILES being
# set by the caller (pick_scan_text, via bash dynamic scoping).
#
# Fixed-name global, not a `local -n` outvar: `local -n` is bash 4.3+ and
# macOS ships bash 3.2 at /bin/bash. pick_scan_text is this function's only
# caller (runs it once per UNIQUE span, still hundreds on a busy screen),
# so a plain global costs nothing here and keeps the call a direct function
# call - no subshell, no command-substitution fork - see the BASH 3.2
# REWRITE note above and the CRITICAL fix round 2 in DECISIONS.md for why
# that fork-per-call cost mattered in the first place.
_pick_classify_span() {
  local span="$1" hkind matched=1
  _PICK_CLASSIFY_KIND=""
  for hkind in "${HANDLER_KINDS[@]}"; do
    if _pick_match_kind "$hkind" "$span"; then
      matched=0
      break
    fi
  done
  [ "$matched" -eq 0 ] || return 0
  case "$hkind" in
    github)
      # Fast mode (below): the local-checkout probe is filesystem work; call
      # it a url and let the open path find the checkout when picked.
      if [ -n "${QUICKLOOK_SCAN_FAST:-}" ]; then
        _PICK_CLASSIFY_KIND='url'
        return 0
      fi
      local mapper
      case "$span" in
        https://gitlab.com/*) mapper=map_gitlab_url ;;
        https://bitbucket.org/*) mapper=map_bitbucket_url ;;
        *) mapper=map_github_url ;;
      esac
      if "$mapper" "$span" && _pick_resolve_github_local "$GH_REPO" "$GH_REST" >/dev/null; then
        _PICK_CLASSIFY_KIND='path'
      else
        _PICK_CLASSIFY_KIND='url'
      fi
      ;;
    vcs)
      if [[ "$span" =~ $_VCS_SHA_RE ]]; then
        _PICK_CLASSIFY_KIND='sha'
      else
        _PICK_CLASSIFY_KIND='ref'
      fi
      ;;
    url) _PICK_CLASSIFY_KIND='url' ;;
    dir) _PICK_CLASSIFY_KIND='dir' ;;
    path)
      local clip_path="$span"
      [[ "$span" =~ ^(.+):([0-9]+)$ ]] && clip_path="${BASH_REMATCH[1]}"
      # QUICKLOOK_SCAN_FAST=1: pluck's model - classify by SHAPE only, zero
      # filesystem work, and defer resolution to the open step (which already
      # resolves across worktrees/roots and reports "not found" gracefully).
      # Pathish = has a slash, a dotted extension (letter-led), or an
      # explicit ~/./ prefix. Prose words have none of these, so the fuzzy
      # bare-name noise never appears in fast mode either.
      if [ -n "${QUICKLOOK_SCAN_FAST:-}" ]; then
        case "$clip_path" in
          */* | '~'*) _PICK_CLASSIFY_KIND='path' ;;
          *)
            [[ "$clip_path" =~ \.[A-Za-z][A-Za-z0-9]{0,7}$ ]] && _PICK_CLASSIFY_KIND='path'
            ;;
        esac
        return 0
      fi
      if _pick_resolve_local "$clip_path" >/dev/null; then
        _PICK_CLASSIFY_KIND='path'
      elif [ -z "${QUICKLOOK_SCAN_SKIP_NAMES:-}" ] && _pick_bare_name_hit_local "$clip_path"; then
        # QUICKLOOK_SCAN_SKIP_NAMES=1 drops the bare-name fuzzy entirely: it
        # is both the noisiest kind (any prose word matching one tracked
        # file) and the most expensive (a list walk per unresolved span).
        _PICK_CLASSIFY_KIND='name'
      fi
      ;;
  esac
}

# pick_scan_text -> see the contract comment above. Pure and
# side-effect-free beyond the read-only filesystem lookups the handler
# registry already does; no clipboard read, no pane read, no fzf, no
# global mutation (see the PURITY note above). Runs on any bash >= 3.2 -
# see the BASH 3.2 REWRITE note above.
pick_scan_text() {
  local screen
  screen="$(_pick_strip_ansi)"

  # Pass 1 (one awk process): tokenize every line into whitespace-split
  # spans, trim wrapping punctuation (matched quotes/parens/brackets/
  # braces/backticks/angle-brackets) and trailing `:,;.`, alternating until
  # neither pass changes anything (same rule the old bash _pick_trim_span
  # used - a sentence-final period OUTSIDE a quoted path ("src/f.md".) and
  # one trapped INSIDE a wrapper (src/f.md.)) both come off; the
  # trailing-punct strip can never eat into a real extension, since it only
  # ever removes from the rightmost position and stops the instant that
  # position isn't `:,;.`), then dedup: the SAME trimmed span seen more
  # than once keeps only its BOTTOM-MOST (largest) line-no, which falls
  # out for free from overwriting `seen[token]` on every repeat while
  # walking the screen top to bottom. Output: `<line-no>\t<token>` per
  # unique span. One awk process replaces what used to be a bash loop
  # calling a `local -n`-based helper once per RAW span (6500+ calls on a
  # busy screen) - see the BASH 3.2 REWRITE note above.
  local dedup
  dedup="$(printf '%s\n' "$screen" | awk -v OFS=$'\t' '
    BEGIN {
      sq = sprintf("%c", 39); dq = sprintf("%c", 34); bq = sprintf("%c", 96)
    }
    function trim(s,    prev, c, first, last) {
      while (1) {
        prev = s
        while (length(s) > 0) {
          c = substr(s, length(s), 1)
          if (c == ":" || c == "," || c == ";" || c == ".") {
            s = substr(s, 1, length(s) - 1)
          } else break
        }
        if (length(s) >= 3) {
          first = substr(s, 1, 1); last = substr(s, length(s), 1)
          if ((first == dq && last == dq) || (first == sq && last == sq) ||
              (first == "(" && last == ")") || (first == "[" && last == "]") ||
              (first == "{" && last == "}") || (first == "<" && last == ">") ||
              (first == bq && last == bq)) {
            s = substr(s, 2, length(s) - 2)
          }
        }
        if (s == prev) break
      }
      return s
    }
    {
      line_no++
      n = split($0, spans, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        if (spans[i] == "") continue
        t = trim(spans[i])
        if (t == "") continue
        seen[t] = line_no
      }
    }
    END {
      for (tok in seen) print seen[tok], tok
    }
  ')"

  [ -z "$dedup" ] && return 0

  # Hoist repo state ONCE for the whole scan, not once per span (see the
  # PERFORMANCE note above): _PICK_ROOT/_PICK_WORKTREES/_PICK_LSFILES/
  # _PICK_LSFILES_LOWER are `local` here, so bash's dynamic scoping makes
  # them visible to every _pick_*_local predicate called below without
  # passing them explicitly. _PICK_LSFILES_LOWER (a single `tr` pass, bash
  # 3.2 has no `${var,,}`) lets _pick_bare_name_hit_local do its
  # case-insensitive match with no per-line lowering - see its comment.
  local _PICK_ROOT _PICK_LSFILES="" _PICK_LSFILES_LOWER=""
  local -a _PICK_WORKTREES=()
  _PICK_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$_PICK_ROOT" ]; then
    local w
    while IFS= read -r w; do
      _PICK_WORKTREES+=("$w")
    done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
    _PICK_LSFILES="$(git -C "$_PICK_ROOT" ls-files 2>/dev/null)"
    _PICK_LSFILES_LOWER="$(printf '%s' "$_PICK_LSFILES" | tr '[:upper:]' '[:lower:]')"
  fi

  # Pass 2: classify each unique span exactly once (still bash - the
  # filesystem-aware _pick_*_local predicates above need it).
  # _pick_classify_span writes its result to the fixed global
  # _PICK_CLASSIFY_KIND (a direct function call, no fork - see its comment
  # above), so this loop stays zero-subprocess-per-span same as before.
  local ranked="" ln tok kind
  while IFS=$'\t' read -r ln tok; do
    [ -z "$tok" ] && continue
    _pick_classify_span "$tok"
    kind="$_PICK_CLASSIFY_KIND"
    [ -n "$kind" ] || continue
    ranked+="$ln"$'\t'"$tok"$'\t'"$kind"$'\n'
  done <<<"$dedup"

  [ -z "$ranked" ] && return 0

  # Pass 3 (awk + sort + awk): tier rank ascending (path > url > sha > ref
  # > dir > name), line-no descending (closer to the bottom first),
  # raw-token lexicographic ascending as the deterministic third tiebreak -
  # same order the old bash `local -A` map + sort-key loop produced,
  # computed here without a bash associative array.
  printf '%s' "$ranked" | awk -F'\t' -v OFS=$'\t' '
    function tier(k) {
      if (k == "path") return 1
      if (k == "url") return 2
      if (k == "sha") return 3
      if (k == "ref") return 4
      if (k == "dir") return 5
      if (k == "name") return 6
      return 9
    }
    { print tier($3), $1, $2, $3 }
  ' | sort -t $'\t' -k1,1n -k2,2nr -k3,3 | awk -F'\t' -v OFS=$'\t' '{ print $3, $4, $2 }'
}

# pick_count_header -> reads pick_scan_text's TAB-delimited output on
# stdin, emits the one-line affordance:
#   N on screen · A path · B url · C sha · D ref · E dir · F name
# listing only the NON-ZERO kinds, fixed order, N = total candidates.
pick_count_header() {
  local kind total=0
  local c_path=0 c_url=0 c_sha=0 c_ref=0 c_dir=0 c_name=0
  while IFS=$'\t' read -r _ kind _; do
    [ -z "$kind" ] && continue
    total=$((total + 1))
    case "$kind" in
      path) c_path=$((c_path + 1)) ;;
      url) c_url=$((c_url + 1)) ;;
      sha) c_sha=$((c_sha + 1)) ;;
      ref) c_ref=$((c_ref + 1)) ;;
      dir) c_dir=$((c_dir + 1)) ;;
      name) c_name=$((c_name + 1)) ;;
    esac
  done
  local -a parts=()
  [ "$c_path" -gt 0 ] && parts+=("$c_path path")
  [ "$c_url" -gt 0 ] && parts+=("$c_url url")
  [ "$c_sha" -gt 0 ] && parts+=("$c_sha sha")
  [ "$c_ref" -gt 0 ] && parts+=("$c_ref ref")
  [ "$c_dir" -gt 0 ] && parts+=("$c_dir dir")
  [ "$c_name" -gt 0 ] && parts+=("$c_name name")
  printf '%s on screen' "$total"
  local p
  for p in "${parts[@]}"; do
    printf ' · %s' "$p"
  done
  printf '\n'
}

# pick_acquire [pane_id] -> see the contract comment above. The ONE
# live-dependency wrapper: everything else in this section is the pure
# core.
pick_acquire() {
  local pane_id="${1:-${QUICKLOOK_PICK_ORIGIN_PANE:-}}"
  if [ -z "$pane_id" ] && command -v jq >/dev/null 2>&1; then
    pane_id="$("$herdr_bin" pane current 2>/dev/null | jq -r '.result.pane.pane_id // empty' 2>/dev/null)"
  fi
  "$herdr_bin" pane read "$pane_id" --source "${QUICKLOOK_PICK_SOURCE:-visible}" --format text 2>/dev/null | pick_scan_text
}
