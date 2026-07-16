# shellcheck shell=bash
# github.sh: github.com/.../blob/... , .../raw/... , raw.githubusercontent.com,
# gitlab.com/.../-/blob/... and bitbucket.org/.../src/... blob URLs. Registry
# entry stays "github" (see HANDOFF.md , SG-01 pinned this filename for the
# SG-03 host extension); the three hosts are sibling shapes dispatched inside
# match_github/handle_github, sharing lib.sh's resolve_github resolver and
# unsafe_relpath traversal guard unchanged.
# shellcheck disable=SC2034  # RESOLVED_* are consumed by the caller (resolve_any_token's caller)

match_github() {
  local raw="$1"
  [ "$(classify_token "$raw")" = "github" ] && return 0
  case "$raw" in
    https://gitlab.com/*/-/blob/*) return 0 ;;
    https://bitbucket.org/*/src/*) return 0 ;;
  esac
  return 1
}

# map_gitlab_url <url>: extract GH_REPO, GH_REST (ref/path, decoded), GH_LINE.
# Accepted shape: gitlab.com/<o>/<r>/-/blob/<ref>/<path>[#L<n>].
map_gitlab_url() {
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
  u="${u%%\?*}" # drop any ?query before splitting
  if [[ "$frag" =~ ^([0-9]+) ]]; then GH_LINE="${BASH_REMATCH[1]}"; fi
  case "$u" in
    https://gitlab.com/*/-/blob/*)
      rest="${u#https://gitlab.com/}"
      GH_REPO="$(printf '%s' "$rest" | cut -d/ -f2)"
      GH_REST="${rest#*/*/-/blob/}"
      ;;
    *) return 1 ;;
  esac
  GH_REST="$(urldecode "$GH_REST")"
  [ -n "$GH_REPO" ] && [ -n "$GH_REST" ]
}

# map_bitbucket_url <url>: extract GH_REPO, GH_REST (ref/path, decoded), GH_LINE.
# Accepted shape: bitbucket.org/<o>/<r>/src/<ref>/<path>[#lines-<n>].
map_bitbucket_url() {
  GH_REPO=""
  GH_REST=""
  GH_LINE=""
  local u="$1" frag="" rest=""
  case "$u" in
    *'#lines-'*)
      frag="${u##*#lines-}"
      u="${u%%#*}"
      ;;
  esac
  u="${u%%\?*}" # drop any ?query before splitting
  if [[ "$frag" =~ ^([0-9]+) ]]; then GH_LINE="${BASH_REMATCH[1]}"; fi
  case "$u" in
    https://bitbucket.org/*/src/*)
      rest="${u#https://bitbucket.org/}"
      GH_REPO="$(printf '%s' "$rest" | cut -d/ -f2)"
      GH_REST="${rest#*/*/src/}"
      ;;
    *) return 1 ;;
  esac
  GH_REST="$(urldecode "$GH_REST")"
  [ -n "$GH_REPO" ] && [ -n "$GH_REST" ]
}

handle_github() {
  local raw="$1" t mapper
  case "$raw" in
    https://gitlab.com/*) mapper=map_gitlab_url ;;
    https://bitbucket.org/*) mapper=map_bitbucket_url ;;
    *) mapper=map_github_url ;;
  esac
  if "$mapper" "$raw" && t="$(resolve_github "$GH_REPO" "$GH_REST")"; then
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
