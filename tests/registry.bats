#!/usr/bin/env bats
# Tests for the handler-registry dispatch (scripts/lib.sh resolve_any_token +
# scripts/handlers/*.sh). Sources lib.sh directly, same fixture shape as
# quicklook.bats: a temp git repo with one worktree and a roots dir.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  HANDLERS_DIR="$BATS_TEST_DIRNAME/../scripts/handlers"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/roots/myrepo/docs" "$FIX/repo/sub"
  git -C "$FIX/repo" init -q -b main
  printf 'hello\n' > "$FIX/repo/sub/inrepo.md"
  printf 'root file\n' > "$FIX/repo/top.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  cd "$FIX/repo"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# ---- each moved kind still resolves as before ----
# NOTE: called directly (not via `run`) because resolve_any_token communicates
# through global RESOLVED_* vars, which `run`'s subshell would not leak back -
# same pattern quicklook.bats already uses for map_github_url/resolve_github.

@test "registry: github blob URL resolves locally as mode=file" {
  # "repo" is the current repo's directory name, matching resolve_github's
  # gname check.
  resolve_any_token "https://github.com/o/repo/blob/main/sub/inrepo.md#L1"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/sub/inrepo.md" ]
  [ "$RESOLVED_LINE" = "1" ]
}

@test "registry: a plain relative path resolves as mode=file" {
  resolve_any_token "top.md:3"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/top.md" ]
  [ "$RESOLVED_LINE" = "3" ]
}

@test "registry: a generic https URL resolves as mode=browser" {
  resolve_any_token "https://example.com/a/b"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
  [ "$RESOLVED_TARGET" = "https://example.com/a/b" ]
}

@test "registry: an unresolvable github URL falls back to mode=browser" {
  resolve_any_token "https://github.com/o/ghostrepo/blob/main/nope.md"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
  [ "$RESOLVED_TARGET" = "https://github.com/o/ghostrepo/blob/main/nope.md" ]
}

@test "registry: non-http(s) schemes never reach mode=browser (url_open only ever fires on an http/https token)" {
  # classify_token's url case is an explicit http://|https:// prefix match;
  # everything else (including a scheme-looking string) falls to the path
  # catch-all. This pins that a clipboard payload spoofing a URL scheme -
  # javascript: (XSS-style), file:// (local-disclosure-style), data: (HTML
  # payload), a non-browser scheme like ftp:// - can NEVER be handed to
  # url_open via mode=browser; each is treated as an ordinary (unresolvable)
  # path token instead, rc 1, no target set. The one regression this closes
  # is classify_token's case pattern ever widening to a bare `*:*` match.
  local t
  for t in 'javascript:alert(document.cookie)' \
           'file:///etc/passwd' \
           'data:text/html,<script>alert(1)</script>' \
           'ftp://evil.example/x'; do
    rc=0
    resolve_any_token "$t" || rc=$?
    [ "$rc" -eq 1 ]
    [ "$RESOLVED_MODE" != "browser" ]
    [ -z "$RESOLVED_MODE" ]
  done
}

# ---- an unmatched token falls through ----

@test "registry: an unresolvable path token returns rc 1, no target set" {
  rc=0
  resolve_any_token "no/such/file.md" || rc=$?
  [ "$rc" -eq 1 ]
  [ -z "$RESOLVED_TARGET" ]
  [ -z "$RESOLVED_MODE" ]
}

@test "registry: a whitespace-only token (bypasses the pane scripts' own [ -z ] empty guard) is a clean no-match, not a crash" {
  # preview-pane.sh/open-in-viewer.sh only special-case a genuinely EMPTY
  # raw token before ever calling resolve_any_token; "   " is non-empty so
  # it reaches here untouched (QUICKLOOK_TOKEN is never trimmed the way
  # clip_read's xargs trims a real clipboard read). It must fall through
  # every handler (git even has no candidate path literally named "   ")
  # and land on rc 1 with no RESOLVED_MODE set, same as any other unmatched
  # path token above - never a spurious match or a crash.
  rc=0
  resolve_any_token "   " || rc=$?
  [ "$rc" -eq 1 ]
  [ -z "$RESOLVED_TARGET" ]
  [ -z "$RESOLVED_MODE" ]
}

# ---- a registered handler wins / first-match ordering ----

@test "registry: github is checked before url (github wins for a github-shaped URL)" {
  # a locally-resolvable github URL structurally also matches url.sh's http(s)
  # pattern; if url.sh won instead of github.sh, mode would be browser with
  # the raw URL as target, not file with a local path.
  resolve_any_token "https://github.com/o/repo/blob/main/top.md"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [[ "$RESOLVED_TARGET" == "$FIX/repo/top.md" ]]
}

@test "registry: a higher-priority handler always wins over a later one, any token" {
  # register a synthetic catch-all kind at the FRONT of HANDLER_KINDS and
  # confirm it claims a token that would otherwise resolve via github/path -
  # proving position, not content, decides ordering.
  match_zzz() { return 0; }
  handle_zzz() {
    RESOLVED_TARGET="zzz-target"
    RESOLVED_LINE=""
    RESOLVED_MODE="zzz-mode"
    return 0
  }
  HANDLER_KINDS=(zzz "${HANDLER_KINDS[@]}")

  resolve_any_token "https://github.com/o/repo/blob/main/top.md"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "zzz-mode" ]
  [ "$RESOLVED_TARGET" = "zzz-target" ]
}

# ---- contract-compliance: every handler exports match_<kind> + handle_<kind> ----

@test "registry: every scripts/handlers/*.sh exports match_<kind> and handle_<kind>" {
  local f kind
  for f in "$HANDLERS_DIR"/*.sh; do
    kind="$(basename "$f" .sh)"
    kind="${kind//-/_}"
    declare -F "match_$kind" >/dev/null || {
      echo "missing match_$kind in $f" >&2
      return 1
    }
    declare -F "handle_$kind" >/dev/null || {
      echo "missing handle_$kind in $f" >&2
      return 1
    }
  done
}

@test "registry: HANDLER_KINDS has path last (the catch-all must not shadow later kinds)" {
  local last="${HANDLER_KINDS[${#HANDLER_KINDS[@]}-1]}"
  [ "$last" = "path" ]
}
