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

# _bare_name_sweep <clip_path> <current-root> -> ABSOLUTE-path matches, one
# per line, from the tracked files of every first-level child repo of every
# QUICKLOOK_ROOTS entry (implicit parents + plugin roots included), skipping
# the current repo (already searched). Only runs after the current-repo
# search found nothing, and stays bounded: one .git stat per child, one
# ls-files per actual repo, 100 lines total.
_bare_name_sweep() {
  local clip_path="$1" cur="$2" r d
  local IFS=':'
  for r in ${QUICKLOOK_ROOTS:-}; do
    [ -n "$r" ] && [ -d "$r" ] || continue
    for d in "$r"/*/; do
      d="${d%/}"
      [ "$d" = "$cur" ] && continue
      [ -e "$d/.git" ] || continue
      git -C "$d" ls-files 2>/dev/null | grep -iF -- "$clip_path" \
        | while IFS= read -r m; do printf '%s/%s\n' "$d" "$m"; done
    done
  done | awk '!seen[$0]++' | head -100
}

# handle_bare_name <clip_path> -> a single or fzf-picked match: sets
# RESOLVED_TARGET (mode=file) and returns 0. Searches the current repo's
# tracked files first; on zero hits there (or no current repo) widens to the
# workspace sweep above. Zero matches everywhere or an fzf cancel: returns 1
# (caller shows its own "not found"). Multiple matches with no fzf
# installed: prints the candidate list itself and exits the CALLING SCRIPT
# directly, exactly matching the pre-refactor inline behavior.
handle_bare_name() {
  local clip_path="$1" root matches n pick scope join
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  matches=""
  scope="this repo"
  join="$root/"
  [ -n "$root" ] && matches="$(git -C "$root" ls-files 2>/dev/null | grep -iF -- "$clip_path" | head -100)"
  if [ -z "$matches" ]; then
    # widen: sibling repos' tracked files, absolute paths (no join prefix)
    matches="$(_bare_name_sweep "$clip_path" "$root")"
    scope="the workspace"
    join=""
  fi
  n="$(printf '%s' "$matches" | grep -c . 2>/dev/null)"
  if [ "$n" -eq 1 ]; then
    RESOLVED_TARGET="$join$matches"
    RESOLVED_LINE=""
    RESOLVED_MODE="file"
    return 0
  elif [ "$n" -gt 1 ]; then
    if command -v fzf >/dev/null 2>&1; then
      pick="$(printf '%s\n' "$matches" | fzf --prompt="$clip_path ▸ " --reverse --cycle --height=100%)" || exit 0
      [ -z "$pick" ] && return 1
      RESOLVED_TARGET="$join$pick"
      RESOLVED_LINE=""
      RESOLVED_MODE="file"
      return 0
    else
      printf '%s matches "%s" in %s (install fzf for an interactive pick):\n\n' "$n" "$clip_path" "$scope"
      printf '%s\n' "$matches"
      printf '\n'
      read -r -n1 -p "press any key to close" _ 2>/dev/null || sleep 2
      exit 0
    fi
  fi
  return 1
}
