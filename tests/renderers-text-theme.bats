#!/usr/bin/env bats
# render_text theme contract (viewer display parity): NO --theme flag by
# default so the user's own bat config decides (same as herdr-file-viewer's
# bare `bat -`); QUICKLOOK_BAT_THEME adds one only when explicitly set.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf 'plain text\n' > "$FIX/doc.txt"
  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/bat"
  # less is exec'd by render_text; print the LESSOPEN it inherited
  printf '#!/usr/bin/env bash\nprintf "LESSOPEN=%%s\\nLESS_ARGS: %%s\\n" "$LESSOPEN" "$*"\n' > "$STUB/less"
  chmod +x "$STUB/bat" "$STUB/less"
  export PATH="$STUB:/usr/bin:/bin"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

@test "render_text: no theme flag by default (bat config decides, like the viewer)" {
  run bash -c "unset QUICKLOOK_BAT_THEME; . '$LIB'; render_text '$FIX/doc.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESSOPEN=|bat --color=always --style=numbers"* ]]
  [[ "$output" != *"--theme"* ]]
}

@test "render_text: QUICKLOOK_BAT_THEME adds an explicit --theme flag" {
  run bash -c "export QUICKLOOK_BAT_THEME=zenburn; . '$LIB'; render_text '$FIX/doc.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--theme=zenburn"* ]]
}

# ---- line-jump parity: the LESSOPEN filter must not shift line numbers ----

@test "the LESSOPEN filter adds no row (so less +N is exact)" {
  local real_bat
  real_bat="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v bat)" || skip "bat not installed"
  local f="$FIX/five.txt"
  seq 1 5 | sed 's/^/line /' > "$f"
  # one rendered row per source line: the object's name lives in the pane
  # LABEL now, so no header row can shift a path:N jump.
  [ "$("$real_bat" --color=always --style=numbers "$f" | wc -l | tr -d ' ')" -eq 5 ]
}

@test "render_text passes the jump through unchanged (no header to skip)" {
  run bash -c "unset QUICKLOOK_BAT_THEME; . '$LIB'; render_text '$FIX/doc.txt' 10"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+10"* ]]
}

@test "render_text's LESSOPEN uses no line-adding decoration" {
  run bash -c "unset QUICKLOOK_BAT_THEME; . '$LIB'; render_text '$FIX/doc.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--style=numbers"* ]]
  [[ "$output" != *"header"* ]]
  [[ "$output" != *"grid"* ]]
}

# ---- short content renders from the TOP of a bottom-anchored pane ----

@test "pad_to_pane_height fills the pane so short content is not bottom-anchored" {
  run bash -c ". '$LIB'; _pane_rows() { printf '10'; }; printf 'a\nb\n' | pad_to_pane_height | wc -l"
  [ "$status" -eq 0 ]
  # 2 real rows padded up to rows-1, leaving the last row for the footer
  [ "$(echo "$output" | tr -d ' ')" -eq 9 ]
}

@test "pad_to_pane_height leaves content longer than the pane untouched" {
  run bash -c ". '$LIB'; _pane_rows() { printf '4'; }; seq 1 20 | pad_to_pane_height | wc -l"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d ' ')" -eq 20 ]
}

@test "_pane_rows is silent and numeric with no controlling tty" {
  # tput reads the size off STDOUT, so in a pipeline or a command
  # substitution it silently returns the terminfo default 24 instead of the
  # real height - the bug this function exists to avoid. It must also not
  # leak a "/dev/tty: Device not configured" line when there is no tty.
  run bash -c ". '$LIB'; _pane_rows"
  [ "$status" -eq 0 ]
  [[ "$output" != *"/dev/tty"* ]]
  [[ "$output" =~ ^[0-9]+$ ]]
}
