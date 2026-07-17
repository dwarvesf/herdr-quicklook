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
# zoo. Each whitespace-delimited, punctuation-trimmed span is walked
# through the SAME HANDLER_KINDS array resolve_any_token uses (github vcs
# url dir path - cheap shape checks first, filesystem-touching dir/path
# last), and the kind is keyed on which handler claimed the span plus its
# RESOLVED_MODE:
#   github -> RESOLVED_MODE file    -> path (resolved to a real local file)
#   github -> RESOLVED_MODE browser -> url  (no local checkout; same bucket
#                                             as any generic url.sh token -
#                                             github.sh never returns rc 1)
#   vcs    -> shape matches _VCS_SHA_RE (vcs.sh's own pattern, reused
#             directly, not re-derived)               -> sha
#   vcs    -> otherwise (a #ref or a PR URL, both dispatch to `gh pr
#             view`)                                  -> ref
#   url    -> (always)                                -> url
#   dir    -> (always; match_dir IS the resolution check - handle_dir is
#              never called here, since its viewer/command split shells
#              out to herdr for a distinction this scan does not need)
#                                                       -> dir
#   path   -> handle_path resolves to a real file       -> path
#   path   -> handle_path fails, but a UNIQUE bare-name hit (the same
#             `git ls-files | grep -iF` matcher bare-name.sh uses, minus
#             its fzf/exit UI)                          -> name
#   anything else                                       -> dropped, not
#                                                          a candidate
# match_path always returns 0 (the catch-all - see the contract at the
# top of this file), so `path` as a KIND is asserted by handle_path's
# RESOLUTION success, never by match_path alone.
#
# Dedup: the SAME raw token seen more than once keeps only the occurrence
# CLOSEST TO THE BOTTOM (the largest line-no) - a plain top-to-bottom walk
# that overwrites its dedup-map entry on every repeat gets this right
# with no extra bookkeeping.
#
# Rank: confidence tier, highest first - path (resolves to a real file) >
# url > sha > ref > dir > name. Tiebreak WITHIN a tier: larger line-no
# first (closer to the bottom = the most recent output).
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
# Action id `pick` -> scripts/pick.sh (no TTY, mirrors scripts/recents.sh):
#   1. captures the origin pane id BEFORE opening the overlay
#      (`herdr pane current | jq -r '.result.pane.pane_id'` - once the
#      pick-pane overlay is focused, `pane current` returns the OVERLAY,
#      not the origin the user was in);
#   2. reads the clipboard token (pick_token / clip_read);
#   3. opens the `pick-pane` overlay, forwarding
#      `--env QUICKLOOK_PICK_ORIGIN_PANE=<id>` (+ `--cwd <origin cwd>` +
#      `--env QUICKLOOK_PICK_CLIP=<clip>` when a clipboard value exists).
# Pane id `pick-pane` -> scripts/pick-pane.sh (real TTY, mirrors
# scripts/recents-pane.sh):
#   4. `pick_acquire "$QUICKLOOK_PICK_ORIGIN_PANE"` -> the candidate list;
#   5. builds the clipboard-first fzf list (row 1 = the clipboard token
#      IF it resolves, deduped out of the on-screen rows below it) +
#      `pick_count_header`'s output as the fzf `--header`;
#   6. Enter -> `export QUICKLOOK_TOKEN=<raw>; exec bash preview-pane.sh`
#      (the SAME open path recents-pane.sh already reuses - resolve +
#      render + record_open, zero new open code);
#   7. Esc -> close, nothing opened; zero candidates and no resolvable
#      clipboard -> an honest empty state, never a crash.
# Confidence-tier order + tiebreak: as above (path > url > sha > ref >
# dir > name; within a tier, larger line-no first).
# -----------------------------------------------------------------------

# _pick_trim_span <span> -> <span> with wrapping punctuation (matched
# quotes/parens/brackets/braces/backticks/angle brackets) and trailing
# `:,;.` stripped, in whichever order applies - the two passes alternate
# until neither changes anything, so a sentence-final period OUTSIDE a
# quoted path ("src/f.md".) and one trapped INSIDE a wrapper (src/f.md.))
# both come off. The trailing-punct pass can never eat into a real file
# extension: it only ever removes from the rightmost position and stops
# the instant that position is not one of `:,;.` (e.g. "lib.sh." ->
# "lib.sh", stopping at "h" - the ".sh" extension is untouched).
_pick_trim_span() {
  local s="$1" prev
  while true; do
    prev="$s"
    while [ -n "$s" ]; do
      case "${s: -1}" in
        : | , | ';' | .) s="${s%?}" ;;
        *) break ;;
      esac
    done
    case "$s" in
      '"'?*'"') s="${s#\"}"; s="${s%\"}" ;;
      "'"?*"'") s="${s#\'}"; s="${s%\'}" ;;
      '('?*')') s="${s#\(}"; s="${s%\)}" ;;
      '['?*']') s="${s#\[}"; s="${s%\]}" ;;
      '{'?*'}') s="${s#\{}"; s="${s%\}}" ;;
      '<'?*'>') s="${s#<}"; s="${s%>}" ;;
      '`'?*'`') s="${s#\`}"; s="${s%\`}" ;;
    esac
    [ "$s" = "$prev" ] && break
  done
  printf '%s' "$s"
}

# _pick_bare_name_hit <clip_path> -> rc 0 iff <clip_path> is a UNIQUE
# case-insensitive substring match against the current repo's tracked
# files. Reuses bare-name.sh's own matcher (same `git ls-files | grep
# -iF`, same unique-hit rule) but stops there - no fzf, no
# exit-the-calling-script branch. handle_bare_name is NOT called: it is
# interactive UI by design (see bare-name.sh's own header comment) and can
# `exit` the calling process outright on an unresolved multi-match, which
# a pure text-in/text-out scan must never risk.
_pick_bare_name_hit() {
  local clip_path="$1" root matches n
  [ -n "$clip_path" ] || return 1
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -z "$root" ] && return 1
  matches="$(git -C "$root" ls-files 2>/dev/null | grep -iF -- "$clip_path" | head -100)"
  n="$(printf '%s' "$matches" | grep -c . 2>/dev/null)"
  [ "$n" -eq 1 ]
}

# _pick_classify_span <span> -> one of path url sha ref dir name on
# stdout, or nothing (a dropped span) - see the contract comment above.
_pick_classify_span() {
  local span="$1" hkind matched=1
  for hkind in "${HANDLER_KINDS[@]}"; do
    if "match_$hkind" "$span"; then
      matched=0
      break
    fi
  done
  [ "$matched" -eq 0 ] || return 0
  case "$hkind" in
    github)
      handle_github "$span"
      case "$RESOLVED_MODE" in
        file) printf 'path' ;;
        browser) printf 'url' ;;
      esac
      ;;
    vcs)
      if [[ "$span" =~ $_VCS_SHA_RE ]]; then
        printf 'sha'
      else
        printf 'ref'
      fi
      ;;
    url) printf 'url' ;;
    dir) printf 'dir' ;;
    path)
      if handle_path "$span"; then
        printf 'path'
      elif _pick_bare_name_hit "$CLIP_PATH"; then
        printf 'name'
      fi
      ;;
  esac
}

# _pick_tier_rank <kind> -> a numeric sort key, lower = higher confidence.
_pick_tier_rank() {
  case "$1" in
    path) printf 1 ;;
    url) printf 2 ;;
    sha) printf 3 ;;
    ref) printf 4 ;;
    dir) printf 5 ;;
    name) printf 6 ;;
    *) printf 9 ;;
  esac
}

# pick_scan_text -> see the contract comment above. Pure and
# side-effect-free beyond the read-only filesystem lookups the handler
# registry already does; no clipboard read, no pane read, no fzf.
pick_scan_text() {
  local line_no=0 line
  local -A _pk_kind=() _pk_line=()
  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    local -a spans=()
    IFS=$' \t' read -ra spans <<<"$line"
    local raw_span trimmed kind
    for raw_span in "${spans[@]}"; do
      [ -z "$raw_span" ] && continue
      trimmed="$(_pick_trim_span "$raw_span")"
      [ -z "$trimmed" ] && continue
      kind="$(_pick_classify_span "$trimmed")"
      [ -z "$kind" ] && continue
      _pk_kind["$trimmed"]="$kind"
      _pk_line["$trimmed"]="$line_no"
    done
  done
  [ "${#_pk_kind[@]}" -eq 0 ] && return 0
  local token
  for token in "${!_pk_kind[@]}"; do
    printf '%s\t%s\t%s\t%s\n' \
      "$(_pick_tier_rank "${_pk_kind[$token]}")" \
      "${_pk_line[$token]}" \
      "$token" \
      "${_pk_kind[$token]}"
  done | sort -t $'\t' -k1,1n -k2,2nr | while IFS=$'\t' read -r _ ln tok knd; do
    printf '%s\t%s\t%s\n' "$tok" "$knd" "$ln"
  done
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
