# shellcheck shell=bash
# bare-name.sh: fuzzy fallback for a path token that resolve() (path.sh)
# could not find directly - grep the repo's tracked files for a
# case-insensitive substring match, fzf-pick when there is more than one hit.
# This is interactive UI (it can print a listing, block on an fzf pick, or
# `exit` the calling script directly on a no-fzf multi-match), not a pure
# target+line+mode resolution, so by design match_bare_name always declines
# automatic dispatch through resolve_any_token. preview-pane.sh calls
# handle_bare_name directly when resolve_any_token reports no match;
# open-in-viewer.sh intentionally does not (zero behavior change from before
# this refactor). See DECISIONS.md: "bare-name is opt-in, not an auto kind".
# shellcheck disable=SC2034  # RESOLVED_* are consumed by the caller (preview-pane.sh)

match_bare_name() { return 1; }

# handle_bare_name <clip_path> -> a single or fzf-picked match: sets
# RESOLVED_TARGET (mode=file) and returns 0. Zero matches, no repo root, or
# an fzf cancel: returns 1 (caller shows its own "not found"). Multiple
# matches with no fzf installed: prints the candidate list itself and exits
# the CALLING SCRIPT directly, exactly matching the pre-refactor inline
# behavior.
handle_bare_name() {
  local clip_path="$1" root matches n pick
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -z "$root" ] && return 1
  matches="$(git -C "$root" ls-files 2>/dev/null | grep -iF -- "$clip_path" | head -100)"
  n="$(printf '%s' "$matches" | grep -c . 2>/dev/null)"
  if [ "$n" -eq 1 ]; then
    RESOLVED_TARGET="$root/$matches"
    RESOLVED_LINE=""
    RESOLVED_MODE="file"
    return 0
  elif [ "$n" -gt 1 ]; then
    if command -v fzf >/dev/null 2>&1; then
      pick="$(printf '%s\n' "$matches" | fzf --prompt="$clip_path ▸ " --reverse --cycle --height=100%)" || exit 0
      [ -z "$pick" ] && return 1
      RESOLVED_TARGET="$root/$pick"
      RESOLVED_LINE=""
      RESOLVED_MODE="file"
      return 0
    else
      printf '%s matches "%s" in this repo (install fzf for an interactive pick):\n\n' "$n" "$clip_path"
      printf '%s\n' "$matches"
      printf '\n'
      read -r -n1 -p "press any key to close" _ 2>/dev/null || sleep 2
      exit 0
    fi
  fi
  return 1
}
