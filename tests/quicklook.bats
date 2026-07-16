#!/usr/bin/env bats
# Tests source scripts/lib.sh directly: the suite runs the production code.
# Fixture: a temp git repo with one worktree and a roots dir, built per test.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  # pwd -P canonicalizes /var vs /private/var so expectations match git output
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/roots/myrepo/docs" "$FIX/repo/sub"
  git -C "$FIX/repo" init -q -b main
  printf 'hello\n' > "$FIX/repo/sub/inrepo.md"
  printf 'root file\n' > "$FIX/repo/top.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture
  git -C "$FIX/repo" worktree add -q "$FIX/wt" -b wt-branch
  printf 'only in worktree\n' > "$FIX/wt/wt-only.md"
  printf 'roots file\n' > "$FIX/roots/myrepo/docs/notes.md"

  cd "$FIX/repo"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS
}

teardown() {
  cd /
  git -C "$FIX/repo" worktree remove --force "$FIX/wt" 2>/dev/null || true
  rm -rf "$FIX"
}

# ---- parse_token ----

@test "parse_token: plain path" {
  parse_token "a/b.md"
  [ "$CLIP_PATH" = "a/b.md" ] && [ -z "$CLIP_LINE" ]
}

@test "parse_token: path:line splits" {
  parse_token "a/b.md:42"
  [ "$CLIP_PATH" = "a/b.md" ] && [ "$CLIP_LINE" = "42" ]
}

@test "parse_token: trailing colon stays in path" {
  parse_token "a/b.md:"
  [ "$CLIP_PATH" = "a/b.md:" ] && [ -z "$CLIP_LINE" ]
}

@test "parse_token: non-numeric suffix stays in path" {
  parse_token "a/b.md:xyz"
  [ "$CLIP_PATH" = "a/b.md:xyz" ] && [ -z "$CLIP_LINE" ]
}

# ---- pick_token (env > arg > clipboard) ----

@test "pick_token: env beats arg" {
  QUICKLOOK_TOKEN="from-env"
  run pick_token "from-arg"
  [ "$output" = "from-env" ]
}

@test "pick_token: arg beats clipboard" {
  clip_read() { printf 'from-clip'; }
  run pick_token "from-arg"
  [ "$output" = "from-arg" ]
}

@test "pick_token: empty env falls through to arg" {
  QUICKLOOK_TOKEN=""
  run pick_token "from-arg"
  [ "$output" = "from-arg" ]
}

@test "pick_token: all empty yields empty" {
  clip_read() { printf ''; }
  run pick_token
  [ -z "$output" ]
}

# ---- resolve ----

@test "resolve: absolute path" {
  run resolve "$FIX/repo/top.md"
  [ "$status" -eq 0 ] && [ "$output" = "$FIX/repo/top.md" ]
}

@test "resolve: cwd-relative path returns absolute" {
  run resolve "sub/inrepo.md"
  [ "$status" -eq 0 ] && [ "$output" = "$PWD/sub/inrepo.md" ]
}

@test "resolve: cross-worktree finds worktree-only file" {
  run resolve "wt-only.md"
  [ "$status" -eq 0 ] && [ "$output" = "$FIX/wt/wt-only.md" ]
}

@test "resolve: QUICKLOOK_ROOTS entry" {
  QUICKLOOK_ROOTS="$FIX/nowhere:$FIX/roots"
  run resolve "myrepo/docs/notes.md"
  [ "$status" -eq 0 ] && [ "$output" = "$FIX/roots/myrepo/docs/notes.md" ]
}

@test "resolve: miss returns rc 1" {
  run resolve "no/such/file.md"
  [ "$status" -eq 1 ]
}
