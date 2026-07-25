#!/usr/bin/env bats
# Tests for the bare-name workspace sweep (handlers/bare-name.sh): when the
# current repo's tracked files have no hit, the fuzzy filename fallback
# widens to every first-level child repo of QUICKLOOK_ROOTS. Non-interactive
# paths only (single hit / no hit); the fzf pick is interactive by design.

setup() {
  export HERDR_BIN_PATH=/usr/bin/false
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/ws/org/repo" "$FIX/ws/org/sibling/docs"
  git -C "$FIX/ws/org/repo" init -q -b main
  printf 'local\n' > "$FIX/ws/org/repo/afile.md"
  git -C "$FIX/ws/org/repo" add -A
  git -C "$FIX/ws/org/repo" -c user.email=t@t -c user.name=t commit -qm f
  git -C "$FIX/ws/org/sibling" init -q -b main
  printf 'remote\n' > "$FIX/ws/org/sibling/docs/uniq-note.md"
  git -C "$FIX/ws/org/sibling" add -A
  git -C "$FIX/ws/org/sibling" -c user.email=t@t -c user.name=t commit -qm f
  cd "$FIX/ws/org/repo"
  QUICKLOOK_ROOTS="$FIX/ws/org"
}

teardown() {
  cd /
  rm -rf "$FIX"
}

@test "bare-name: a filename tracked only in a sibling repo resolves absolute" {
  handle_bare_name "uniq-note"
  [ "$RESOLVED_TARGET" = "$FIX/ws/org/sibling/docs/uniq-note.md" ]
  [ "$RESOLVED_MODE" = "file" ]
}

@test "bare-name: a current-repo hit still wins, the sweep never runs" {
  # same name tracked in BOTH; the current repo's must win as the single hit
  printf 'shadow\n' > "$FIX/ws/org/sibling/afile.md"
  git -C "$FIX/ws/org/sibling" add -A
  git -C "$FIX/ws/org/sibling" -c user.email=t@t -c user.name=t commit -qm s
  handle_bare_name "afile"
  [ "$RESOLVED_TARGET" = "$FIX/ws/org/repo/afile.md" ]
}

@test "bare-name: no hit anywhere returns 1" {
  ! handle_bare_name "no-such-file-anywhere"
}

@test "bare-name: outside any repo, the sweep alone still resolves" {
  mkdir -p "$FIX/ws/nowhere"
  cd "$FIX/ws/nowhere"
  QUICKLOOK_ROOTS="$FIX/ws/org"
  handle_bare_name "uniq-note"
  [ "$RESOLVED_TARGET" = "$FIX/ws/org/sibling/docs/uniq-note.md" ]
}
