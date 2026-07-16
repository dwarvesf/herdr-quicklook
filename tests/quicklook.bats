#!/usr/bin/env bats
# Tests source scripts/lib.sh directly: the suite runs the production code.
# Fixture: a temp git repo with one worktree and a roots dir, built per test.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  # pwd -P: canonicalize so expectations match git's output (/var vs /private/var on macOS)
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # main repo
  mkdir -p "$FIX/roots/myrepo/docs" "$FIX/repo/sub"
  git -C "$FIX/repo" init -q -b main
  printf 'hello\n' > "$FIX/repo/sub/inrepo.md"
  printf 'root file\n' > "$FIX/repo/top.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture
  # a worktree with a file that exists ONLY there
  git -C "$FIX/repo" worktree add -q "$FIX/wt" -b wt-branch
  printf 'only in worktree\n' > "$FIX/wt/wt-only.md"
  # a roots-resolvable repo
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

# ---- pick_token ----

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

# ---- classify_token ----

@test "classify: blob URL is github" {
  run classify_token "https://github.com/o/r/blob/main/src/x.go"
  [ "$output" = "github" ]
}

@test "classify: github raw URL is github" {
  run classify_token "https://github.com/o/r/raw/main/x.md"
  [ "$output" = "github" ]
}

@test "classify: raw.githubusercontent is github" {
  run classify_token "https://raw.githubusercontent.com/o/r/main/x.md"
  [ "$output" = "github" ]
}

@test "classify: generic https is url" {
  run classify_token "https://example.com/a/b"
  [ "$output" = "url" ]
}

@test "classify: http is url" {
  run classify_token "http://example.com"
  [ "$output" = "url" ]
}

@test "classify: plain path is path" {
  run classify_token "sub/inrepo.md:12"
  [ "$output" = "path" ]
}

# ---- map_github_url ----

@test "map: blob URL extracts repo, rest, line" {
  map_github_url "https://github.com/own/proj/blob/main/src/a.go#L42"
  [ "$GH_REPO" = "proj" ] && [ "$GH_REST" = "main/src/a.go" ] && [ "$GH_LINE" = "42" ]
}

@test "map: line range keeps start line" {
  map_github_url "https://github.com/o/r/blob/main/a.md#L42-L60"
  [ "$GH_LINE" = "42" ]
}

@test "map: no fragment means no line" {
  map_github_url "https://github.com/o/r/blob/main/a.md"
  [ -z "$GH_LINE" ]
}

@test "map: percent-encoding decodes" {
  map_github_url "https://github.com/o/r/blob/main/my%20file.md"
  [ "$GH_REST" = "main/my file.md" ]
}

@test "map: raw.githubusercontent shape" {
  map_github_url "https://raw.githubusercontent.com/o/proj/main/docs/x.md"
  [ "$GH_REPO" = "proj" ] && [ "$GH_REST" = "main/docs/x.md" ]
}

@test "map: /raw/ blob shape extraction" {
  map_github_url "https://github.com/o/proj/raw/main/docs/x.md"
  [ "$GH_REPO" = "proj" ] && [ "$GH_REST" = "main/docs/x.md" ]
}

@test "map: query string is stripped before splitting" {
  map_github_url "https://github.com/o/r/blob/main/src/x.go?plain=1"
  [ "$GH_REST" = "main/src/x.go" ]
}

@test "map: query plus fragment still yields the line" {
  map_github_url "https://github.com/o/r/blob/main/a.md?plain=1#L10"
  [ "$GH_REST" = "main/a.md" ] && [ "$GH_LINE" = "10" ]
}

@test "map: literal + in path stays a plus (path decoding, not query)" {
  map_github_url "https://github.com/o/r/blob/main/docs/c++.md"
  [ "$GH_REST" = "main/docs/c++.md" ]
}

@test "map: backslash escapes are not interpreted by urldecode" {
  map_github_url 'https://github.com/o/r/blob/main/a\nb.md'
  # the \n must survive as two literal chars, not become a newline
  [ "$GH_REST" = 'main/a\nb.md' ]
}

@test "map: non-github URL fails" {
  run map_github_url "https://example.com/o/r/blob/main/a.md"
  [ "$status" -ne 0 ]
}

# ---- resolve_github traversal/absolute rejection (security) ----

@test "resolve_github: absolute smuggle (double slash) is refused" {
  # blob/main//etc/hosts -> rest main//etc/hosts -> candidate /etc/hosts
  run resolve_github "repo" "main//etc/passwd"
  [ "$status" -eq 1 ]
}

@test "resolve_github: dotdot traversal is refused" {
  run resolve_github "repo" "main/../../../etc/passwd"
  [ "$status" -eq 1 ]
}

@test "unsafe_relpath: classifies absolute and traversal, allows plain" {
  run unsafe_relpath "/etc/passwd";    [ "$status" -eq 0 ]
  run unsafe_relpath "../x";           [ "$status" -eq 0 ]
  run unsafe_relpath "a/../b";         [ "$status" -eq 0 ]
  run unsafe_relpath "a/b/c.md";       [ "$status" -eq 1 ]
}

# ---- resolve ----

@test "resolve: absolute path" {
  run resolve "$FIX/repo/top.md"
  [ "$status" -eq 0 ] && [ "$output" = "$FIX/repo/top.md" ]
}

@test "resolve: cwd-relative path" {
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

# ---- resolve_github ----

@test "resolve_github: repo-name match in current repo" {
  # current repo dir is named "repo"; url repo must match that name
  run resolve_github "repo" "main/sub/inrepo.md"
  [ "$status" -eq 0 ] && [ "$output" = "$FIX/repo/sub/inrepo.md" ]
}

@test "resolve_github: ref containing slash resolves via successive split" {
  run resolve_github "repo" "feat/nested-ref/sub/inrepo.md"
  [ "$status" -eq 0 ] && [ "$output" = "$FIX/repo/sub/inrepo.md" ]
}

@test "resolve_github: roots/<repo>/<path> match" {
  QUICKLOOK_ROOTS="$FIX/roots"
  run resolve_github "myrepo" "main/docs/notes.md"
  [ "$status" -eq 0 ] && [ "$output" = "$FIX/roots/myrepo/docs/notes.md" ]
}

@test "resolve_github: unresolvable returns rc 1 (browser fallback)" {
  run resolve_github "ghost" "main/no/file.md"
  [ "$status" -eq 1 ]
}

# ---- v0.1 regression ----

@test "regression: clipboard path flow unchanged with no env/arg" {
  clip_read() { printf 'sub/inrepo.md:1'; }
  raw="$(pick_token)"
  [ "$raw" = "sub/inrepo.md:1" ]
  [ "$(classify_token "$raw")" = "path" ]
  parse_token "$raw"
  run resolve "$CLIP_PATH"
  [ "$status" -eq 0 ] && [ "$output" = "$PWD/sub/inrepo.md" ]
}
