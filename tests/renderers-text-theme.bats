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
  printf '#!/usr/bin/env bash\nprintf "LESSOPEN=%%s\\n" "$LESSOPEN"\n' > "$STUB/less"
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
