#!/usr/bin/env bats
# Tests for the GitLab + Bitbucket blob-URL host shapes added to
# scripts/handlers/github.sh (SG-03, more-hosts). Same fixture shape as
# registry.bats: a temp git repo, exercised through resolve_any_token so the
# whole registry path (match_github -> handle_github -> shared resolve_github
# + unsafe_relpath) is proven end to end, not just the per-host mapper.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo/sub"
  git -C "$FIX/repo" init -q -b main
  printf 'hello\n' > "$FIX/repo/sub/inrepo.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  cd "$FIX/repo"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# ---- match_github: new host shapes accepted, unrelated hosts fall through ----

@test "match_github: gitlab blob URL is accepted" {
  match_github "https://gitlab.com/o/repo/-/blob/main/sub/inrepo.md#L1"
}

@test "match_github: bitbucket blob URL is accepted" {
  match_github "https://bitbucket.org/o/repo/src/main/sub/inrepo.md#lines-1"
}

@test "match_github: a non-matching host falls through" {
  ! match_github "https://example.com/o/r/blob/main/a.md"
}

@test "match_github: a gitlab non-blob URL (e.g. repo root) falls through" {
  ! match_github "https://gitlab.com/o/repo"
}

@test "match_github: a bitbucket non-src URL (e.g. repo root) falls through" {
  ! match_github "https://bitbucket.org/o/repo"
}

# ---- map_gitlab_url ----

@test "map_gitlab_url: extracts repo, rest, line" {
  map_gitlab_url "https://gitlab.com/own/proj/-/blob/main/src/a.go#L42"
  [ "$GH_REPO" = "proj" ]
  [ "$GH_REST" = "main/src/a.go" ]
  [ "$GH_LINE" = "42" ]
}

@test "map_gitlab_url: no line anchor leaves GH_LINE empty" {
  map_gitlab_url "https://gitlab.com/o/proj/-/blob/main/docs/x.md"
  [ "$GH_REPO" = "proj" ]
  [ "$GH_REST" = "main/docs/x.md" ]
  [ "$GH_LINE" = "" ]
}

@test "map_gitlab_url: non-gitlab URL fails" {
  run map_gitlab_url "https://example.com/o/r/-/blob/main/a.md"
  [ "$status" -ne 0 ]
}

# ---- map_bitbucket_url ----

@test "map_bitbucket_url: extracts repo, rest, line" {
  map_bitbucket_url "https://bitbucket.org/own/proj/src/main/src/a.go#lines-42"
  [ "$GH_REPO" = "proj" ]
  [ "$GH_REST" = "main/src/a.go" ]
  [ "$GH_LINE" = "42" ]
}

@test "map_bitbucket_url: no line anchor leaves GH_LINE empty" {
  map_bitbucket_url "https://bitbucket.org/o/proj/src/main/docs/x.md"
  [ "$GH_REPO" = "proj" ]
  [ "$GH_REST" = "main/docs/x.md" ]
  [ "$GH_LINE" = "" ]
}

@test "map_bitbucket_url: non-bitbucket URL fails" {
  run map_bitbucket_url "https://example.com/o/r/src/main/a.md"
  [ "$status" -ne 0 ]
}

# ---- end-to-end resolution via resolve_any_token ----

@test "registry: gitlab blob URL resolves locally as mode=file" {
  resolve_any_token "https://gitlab.com/o/repo/-/blob/main/sub/inrepo.md#L1"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/sub/inrepo.md" ]
  [ "$RESOLVED_LINE" = "1" ]
}

@test "registry: bitbucket blob URL resolves locally as mode=file" {
  resolve_any_token "https://bitbucket.org/o/repo/src/main/sub/inrepo.md#lines-1"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/sub/inrepo.md" ]
  [ "$RESOLVED_LINE" = "1" ]
}

@test "registry: unresolvable gitlab URL falls back to mode=browser" {
  resolve_any_token "https://gitlab.com/o/ghostrepo/-/blob/main/nope.md"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
  [ "$RESOLVED_TARGET" = "https://gitlab.com/o/ghostrepo/-/blob/main/nope.md" ]
}

@test "registry: unresolvable bitbucket URL falls back to mode=browser" {
  resolve_any_token "https://bitbucket.org/o/ghostrepo/src/main/nope.md"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
  [ "$RESOLVED_TARGET" = "https://bitbucket.org/o/ghostrepo/src/main/nope.md" ]
}

@test "registry: gitlab URL with a nested (multi-segment) ref resolves via successive split" {
  resolve_any_token "https://gitlab.com/o/repo/-/blob/feat/nested-ref/sub/inrepo.md#L1"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/sub/inrepo.md" ]
}

# ---- traversal / absolute-smuggle negative controls, re-asserted per host ----
# Same smuggle shapes github.sh's own tests already close for github.com
# (registry.bats / quicklook.bats), re-run through the full GitLab and
# Bitbucket URL parse -> resolve_github -> unsafe_relpath path end to end.

@test "gitlab: absolute-slash smuggle (//etc/passwd) is refused, falls back to browser" {
  resolve_any_token "https://gitlab.com/o/repo/-/blob/main//etc/passwd"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
}

@test "gitlab: dotdot traversal smuggle (../../etc/passwd) is refused, falls back to browser" {
  resolve_any_token "https://gitlab.com/o/repo/-/blob/main/../../../etc/passwd"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
}

@test "bitbucket: absolute-slash smuggle (//etc/passwd) is refused, falls back to browser" {
  resolve_any_token "https://bitbucket.org/o/repo/src/main//etc/passwd"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
}

@test "bitbucket: dotdot traversal smuggle (../../etc/passwd) is refused, falls back to browser" {
  resolve_any_token "https://bitbucket.org/o/repo/src/main/../../../etc/passwd"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "browser" ]
}
