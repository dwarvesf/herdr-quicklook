#!/usr/bin/env bats
# Script-level tests for the token dispatch in preview-pane.sh: run the actual
# script with a github / path / url token and assert where it ends up. `less`
# is stubbed to print the file it was asked to open (preview-pane execs it with
# the resolved target as the last argument), so we can assert the resolved path
# without a real pager or herdr server. This is the coverage the unit tests
# (which call lib.sh functions directly) do not give: it proves the case block
# in the consumer script is wired correctly.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/preview-pane.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # a repo whose DIRECTORY NAME is "myrepo" so a github URL for repo "myrepo" matches
  mkdir -p "$FIX/myrepo"
  git -C "$FIX/myrepo" init -q -b main
  printf 'line1\nline2\nline3\n' > "$FIX/myrepo/f.md"
  git -C "$FIX/myrepo" add -A
  git -C "$FIX/myrepo" -c user.email=t@t -c user.name=t commit -qm fix

  # stubs: `less` prints its args (so the target path is visible); `herdr`
  # answers config-dir with empty; `bat` absent so preview-pane takes the less path;
  # `open` logs the URL it was asked to open instead of actually launching a
  # browser (the browser-fallback test below asserts against OPEN_LOG). Without
  # this stub, a browser-mode token on a real macOS box would resolve PATH's
  # /usr/bin/open and pop a real foreground browser window during `bats tests/`.
  STUB="$(mktemp -d)"
  OPEN_LOG="$(mktemp)"
  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS: %%s\\n" "$*"\n' > "$STUB/less"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/herdr"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> "%s"\n' "$OPEN_LOG" > "$STUB/open"
  chmod +x "$STUB/less" "$STUB/herdr" "$STUB/open"

  cd "$FIX/myrepo"
  # keep git/coreutils reachable but force our less + no bat
  export PATH="$STUB:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS
  # make sure bat is not found even if installed system-wide
  bat() { return 127; }
  export -f bat 2>/dev/null || true
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
  rm -f "$OPEN_LOG"
}

@test "dispatch: github blob URL opens the local file at the line" {
  export QUICKLOOK_TOKEN="https://github.com/owner/myrepo/blob/main/f.md#L3"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # resolved to the LOCAL file, with the +3 line jump
  [[ "$output" == *"$FIX/myrepo/f.md"* ]]
  [[ "$output" == *"+3"* ]]
}

@test "dispatch: a plain relative path token opens locally" {
  export QUICKLOOK_TOKEN="f.md:2"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FIX/myrepo/f.md"* ]]
  [[ "$output" == *"+2"* ]]
}

@test "dispatch: a github URL with no matching local checkout falls back to the browser, not a file" {
  export QUICKLOOK_TOKEN="https://github.com/owner/ghostrepo/blob/main/nope.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # no local file resolved -> browser fallback path, less never called with a target
  ! [[ "$output" == *"LESS_ARGS"*"nope.md"* ]]
  # and it IS the browser fallback, not a silent no-op: url_open (stubbed as
  # `open` above) received exactly the original ghost URL, unmodified.
  [ "$(cat "$OPEN_LOG")" = "https://github.com/owner/ghostrepo/blob/main/nope.md" ]
}

@test "pager env: sourcing lib.sh forces a UTF-8 charset for less" {
  run bash -c "unset LESSCHARSET LANG; . scripts/lib.sh; printf %s::%s \"\$LESSCHARSET\" \"\$LANG\""
  [ "$status" -eq 0 ]
  [[ "$output" == "utf-8::en_US.UTF-8" ]]
}

@test "pager env: an explicit user locale is not clobbered" {
  run bash -c "export LESSCHARSET=latin1 LANG=fr_FR.UTF-8; . scripts/lib.sh; printf %s::%s \"\$LESSCHARSET\" \"\$LANG\""
  [ "$status" -eq 0 ]
  [[ "$output" == "latin1::fr_FR.UTF-8" ]]
}
