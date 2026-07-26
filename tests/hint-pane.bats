#!/usr/bin/env bats
# Script-level tests for hint-pane.sh's bottom-align paint: a snapshot
# SHORTER than the overlay pads blank rows on TOP (the origin pane anchors
# content to the bottom), never floats up leaving a blank band below. Headless:
# `rows` comes from `stty size <$tty_in` and stty resolves via PATH, so a
# stub stty pins the overlay height; /dev/tty is unreadable under bats so
# tty_in falls back to /dev/stdin, and a piped `q` exits the key loop.

setup() {
  export HERDR_BIN_PATH=/usr/bin/false
  PANE="$BATS_TEST_DIRNAME/../scripts/hint-pane.sh"

  SNAP="$(mktemp)"
  TOK="$(mktemp)"
  printf 'open sub/inrepo.md now\nline two\nline three\nline four\nline five\n' > "$SNAP"
  printf 'sub/inrepo.md\t1\t\tsub/inrepo.md\n' > "$TOK"
  export QUICKLOOK_HINT_SNAP_FILE="$SNAP"
  export QUICKLOOK_HINT_TOKENS_FILE="$TOK"

  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nprintf "24 80\\n"\n' > "$STUB/stty"
  chmod +x "$STUB/stty"
  export PATH="$STUB:/usr/bin:/bin"
}

teardown() {
  rm -rf "$STUB" 2>/dev/null
  # SNAP/TOK are deleted by the pane's own cleanup
}

@test "hint-pane: a short snapshot is bottom-aligned (pad rows on top, none below)" {
  run bash "$PANE" <<<'q'
  [ "$status" -eq 0 ]
  # 24 rows - 5 snapshot lines = 19 blank pad rows between HOME and the
  # first dimmed snapshot line, in the first paint. printf -v, not $(...):
  # command substitution strips the trailing newlines the pad IS made of.
  local pad
  printf -v pad '\n%.0s' {1..19}
  expected=$'\033[H'"${pad}"$'\033[2;90m'
  [[ "$output" == *"$expected"* ]]
  # the old top-aligned form (content directly after HOME) must be gone
  bad=$'\033[H\033[2;90m'
  [[ "$output" != *"$bad"* ]]
}

@test "hint-pane: a snapshot as tall as the overlay gets no pad" {
  # 24 lines exactly fills rows=24: content starts right after HOME
  for i in $(seq 1 24); do printf 'row %s\n' "$i"; done > "$SNAP"
  run bash "$PANE" <<<'q'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[H\033[2;90m'* ]]
}

# The banner is the overlay's proof of life. On a sparse pane (a PR view has
# 2-3 openable tokens) the overlay differs from the pane under it by 2-3
# characters, and a real user pressed the key twice, saw "nothing", and
# dismissed two perfectly good overlays unseen (plugin log, 00:20:22 and
# 00:20:44). The banner makes a successful open unmistakable.
@test "hint-pane: paints the banner row with the target count" {
  run bash "$PANE" <<<'q'
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 target(s)"* ]]
  [[ "$output" == *"q cancels"* ]]
}

@test "hint-pane: QUICKLOOK_HINT_BANNER=0 suppresses the banner" {
  QUICKLOOK_HINT_BANNER=0 run bash "$PANE" <<<'q'
  [ "$status" -eq 0 ]
  [[ "$output" != *"target(s)"* ]]
}
