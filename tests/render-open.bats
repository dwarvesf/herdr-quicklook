#!/usr/bin/env bats
# Tests for scripts/render-open.sh, the LESSOPEN input preprocessor that every
# file-backed preview runs through.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  LIB="$ROOT/scripts/lib.sh"
  OPEN="$ROOT/scripts/render-open.sh"
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf '# Title\n\nSome **bold** text.\n' > "$FIX/doc.md"
  printf 'plain text\n' > "$FIX/doc.txt"
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# glow stub that reports whether it was given a colour-forcing environment,
# plus a `file` passthrough so match_render_markdown still works.
stub_glow_reporting_colour() {
  STUB="$(mktemp -d)"
  cat > "$STUB/glow" <<'SH'
#!/usr/bin/env bash
printf 'CLICOLOR_FORCE=[%s]\n' "${CLICOLOR_FORCE:-}"
SH
  chmod +x "$STUB/glow"
  export PATH="$STUB:/usr/bin:/bin"
}

# The regression: render_command_in_pager sets CLICOLOR_FORCE=1, and when
# rendering moved into this preprocessor the trick was left behind. glow is
# termenv-based and drops to a NO-COLOUR profile whenever stdout is not a tty
# -- and in here its stdout is a pipe. The symptom was a markdown preview that
# rendered structurally correct but monochrome: bold survived, colour did not.
@test "render-open.sh forces colour for termenv tools (stdout is a pipe here)" {
  stub_glow_reporting_colour
  run bash "$OPEN" "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLICOLOR_FORCE=[1]"* ]]
}

# LESSOPEN's contract: no output means "show the file raw". A kind with no
# emit_ half (an image pushed onto the stack with `:e`) must produce NOTHING,
# not a screen of blank padding -- less reads any output at all as "handled".
@test "render-open.sh emits nothing for a kind with no emit_ half" {
  stub_glow_reporting_colour
  run bash "$OPEN" "$FIX/doc.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "render-open.sh emits nothing for a missing path" {
  run bash "$OPEN" "$FIX/nope.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "render-open.sh emits nothing when given no argument" {
  run bash "$OPEN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
