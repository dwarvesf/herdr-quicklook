# shellcheck shell=bash
# github.sh: github.com/.../blob/... , .../raw/... and raw.githubusercontent.com
# URLs. Wired to classify_token / map_github_url / resolve_github in lib.sh.
# SG-03 (more-hosts) EXTENDS this exact file for GitLab/Bitbucket blob URLs;
# keep this filename, see HANDOFF.md.
# shellcheck disable=SC2034  # RESOLVED_* are consumed by the caller (resolve_any_token's caller)

match_github() {
  [ "$(classify_token "$1")" = "github" ]
}

handle_github() {
  local raw="$1" t
  if map_github_url "$raw" && t="$(resolve_github "$GH_REPO" "$GH_REST")"; then
    RESOLVED_TARGET="$t"
    RESOLVED_LINE="$GH_LINE"
    RESOLVED_MODE="file"
    return 0
  fi
  # no local checkout matches: the browser is the right place after all
  RESOLVED_TARGET="$raw"
  RESOLVED_LINE=""
  RESOLVED_MODE="browser"
  return 0
}
