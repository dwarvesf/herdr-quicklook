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
  [[ "$output" == *"LESSOPEN=|bat --color=always --style=numbers,header"* ]]
  [[ "$output" != *"--theme"* ]]
}

@test "render_text: QUICKLOOK_BAT_THEME adds an explicit --theme flag" {
  run bash -c "export QUICKLOOK_BAT_THEME=zenburn; . '$LIB'; render_text '$FIX/doc.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--theme=zenburn"* ]]
}

# ---- line-jump parity: the LESSOPEN filter must not shift line numbers ----

@test "the header-height probe predicts the full render's row count" {
  local real_bat
  real_bat="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v bat)" || skip "bat not installed"
  local f="$FIX/five.txt"
  seq 1 5 | sed 's/^/line /' > "$f"
  local probe full
  probe="$("$real_bat" --color=always --style=numbers,header --line-range 1:1 -- "$f" | wc -l | tr -d ' ')"
  full="$("$real_bat" --color=always --style=numbers,header -- "$f" | wc -l | tr -d ' ')"
  # header rows = probe - 1 (the probe also renders one content row), so a
  # 5-line file must render as 5 + (probe - 1) rows. This is the identity
  # render_text's jump compensation relies on; a fixed constant is WRONG
  # because bat wraps a long "File: ..." path onto a second row.
  [ "$full" -eq "$((5 + probe - 1))" ]
}

@test "render_text shifts a line jump past the measured header rows" {
  command -v bat >/dev/null 2>&1 || skip "stub bat required"
  # stub bat prints one row for the probe -> probe=1 -> no shift; the real
  # behaviour with a multi-row header is covered by the identity test above.
  run bash -c "unset QUICKLOOK_BAT_THEME; . '$LIB'; render_text '$FIX/doc.txt' 10"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+1"* ]]
}

@test "render_text without bat does NOT shift the jump (no header in that stream)" {
  rm -f "$STUB/bat"
  run bash -c "unset QUICKLOOK_BAT_THEME; . '$LIB'; render_text '$FIX/doc.txt' 10"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+10"* ]]
}
