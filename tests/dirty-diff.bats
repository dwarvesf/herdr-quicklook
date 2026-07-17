#!/usr/bin/env bats
# Script-level tests for scripts/dirty-diff.sh (the lesskey `d` binding's
# target, see ../lesskey). `git` is stubbed to record its argv ONE ARG PER
# LINE (proving the target stays a single post-`--` element, no injection,
# even when it contains a space) and to control the diff output; `less` and
# `delta` are stubbed no-ops so the nested-pager legs never try to attach a
# real TTY under bats. The clean-file path's own read-a-key pause degrades to
# a bounded `sleep 2` with stdin closed (see the script's own comment), so
# those two tests take ~2s each.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/dirty-diff.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo"

  STUB="$(mktemp -d)"
  GIT_LOG="$STUB/git.log"
  # shellcheck disable=SC2016
  cat >"$STUB/git" <<GITSTUB
#!/usr/bin/env bash
{
  printf 'ARGC=%d\n' "\$#"
  i=0
  for a in "\$@"; do
    i=\$((i + 1))
    printf 'ARG%d=[%s]\n' "\$i" "\$a"
  done
  printf -- '---\n'
} >> "$GIT_LOG"
if [ -n "\${DIRTY_DIFF_STUB_OUTPUT:-}" ]; then
  printf '%s\n' "\$DIRTY_DIFF_STUB_OUTPUT"
fi
GITSTUB
  chmod +x "$STUB/git"

  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS: %%s\\n" "$*"\ncat\n' >"$STUB/less"
  chmod +x "$STUB/less"

  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/herdr"
  chmod +x "$STUB/herdr"

  # PATH deliberately excludes delta (not stubbed here): these tests exercise
  # the no-delta fallback by default. A dedicated test below adds a delta
  # stub to prove the other branch.
  export PATH="$STUB:/usr/bin:/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
  unset QUICKLOOK_ROOTS
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

@test "dirty-diff: a dirty file pipes the diff through less (no delta)" {
  export DIRTY_DIFF_STUB_OUTPUT="+CHANGED LINE"
  run bash "$SCRIPT" "$FIX/repo/f.txt" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" == *"CHANGED LINE"* ]]
  # single post-`--` arg: git was called with exactly 6 args, the last one
  # (ARG6) being the untouched file path, ARG5 being the bare `--` separator.
  grep -qxF 'ARGC=6' "$GIT_LOG"
  grep -qxF "ARG5=[--]" "$GIT_LOG"
  grep -qxF "ARG6=[$FIX/repo/f.txt]" "$GIT_LOG"
}

@test "dirty-diff: delta is used when present on PATH" {
  printf '#!/usr/bin/env bash\nprintf "DELTA_RAN\\n"\ncat >/dev/null\n' >"$STUB/delta"
  chmod +x "$STUB/delta"
  export DIRTY_DIFF_STUB_OUTPUT="+x"
  run bash "$SCRIPT" "$FIX/repo/f.txt" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELTA_RAN"* ]]
  [[ "$output" == *"LESS_ARGS:"* ]]
}

@test "dirty-diff: a clean file prints the no-changes notice, no pager" {
  unset DIRTY_DIFF_STUB_OUTPUT
  run bash "$SCRIPT" "$FIX/repo/f.txt" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"no unstaged changes for $FIX/repo/f.txt"* ]]
  [[ "$output" != *"LESS_ARGS:"* ]]
  grep -qxF 'ARGC=6' "$GIT_LOG"
}

@test "dirty-diff: a filename with a space stays one arg (negative control)" {
  export DIRTY_DIFF_STUB_OUTPUT="+x"
  mkdir -p "$FIX/repo/sub dir"
  run bash "$SCRIPT" "$FIX/repo/sub dir/my file.txt" </dev/null
  [ "$status" -eq 0 ]
  grep -qxF 'ARGC=6' "$GIT_LOG"
  grep -qxF "ARG6=[$FIX/repo/sub dir/my file.txt]" "$GIT_LOG"
  # and the containing dir (ARG2, the -C value) kept its space too
  grep -qxF "ARG2=[$FIX/repo/sub dir]" "$GIT_LOG"
}

@test "dirty-diff: an untracked file (never added to git) shows no unstaged changes, same as a clean file" {
  # Every test above drives a FAKE git that returns a canned
  # DIRTY_DIFF_STUB_OUTPUT, so none of them prove what `git diff -- <path>`
  # actually does for a path that was never added to the index (git diff
  # only shows unstaged changes to TRACKED files, so an untracked file
  # produces empty output too, same as a clean one - it does not error or
  # print the file's full contents as a "whole file added" diff). Swap in
  # the real git binary for this one test to pin that real behavior, not
  # the stub's assumption of it.
  printf '#!/usr/bin/env bash\nexec /usr/bin/git "$@"\n' >"$STUB/git"
  chmod +x "$STUB/git"
  git -C "$FIX/repo" init -q -b main
  printf 'tracked\n' >"$FIX/repo/tracked.txt"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm init
  printf 'never added\n' >"$FIX/repo/untracked.txt"
  run bash "$SCRIPT" "$FIX/repo/untracked.txt" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"no unstaged changes for $FIX/repo/untracked.txt"* ]]
  [[ "$output" != *"LESS_ARGS:"* ]]
}

@test "dirty-diff: no file argument is a no-op" {
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$GIT_LOG" ]
}
