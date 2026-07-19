#!/usr/bin/env bats
# Tests for scripts/renderers/fallback.sh, the always-on render-registry
# guard (v0.4). This renderer IS every other renderer's negative control -
# fallback.sh always matches (RENDER_KINDS keeps it last, see
# tests/render-registry.bats for the ordering guarantees), so its own tests
# are the reference for "an unknown/binary file never dumps raw bytes".
#
# PATH is rebuilt PER TEST (never inherited) so "tool absent" is a real,
# deterministic absence, not an artifact of what happens to be installed on
# the dev box - same convention as tests/handlers-dir.bats /
# tests/recents.bats: deliberately excludes /opt/homebrew/bin and
# /usr/local/bin so a brew/cargo-installed hexyl/chafa never leaks in.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # A real binary fixture carrying an actual terminal escape sequence
  # (ESC [ 2 J - clear screen) plus NUL/high bytes - the concrete "this
  # must never reach the pane un-hexed" payload the safety tests assert
  # against.
  printf '\x1b[2J\x00\x01\xffHELLO\x02world' > "$FIX/binary.bin"
  printf 'hello world\nline two\n' > "$FIX/text.md"
  printf '\x1b[2J\x00\x01\xffHELLO\x02world' > "$FIX/noext"
  printf '\x1b[2J\x00PNGISH\x01' > "$FIX/pic.png"
  printf '\x1b[2J\x00XYZISH\x01' > "$FIX/blob.xyz"

  # STUB: fake tools for the "present" branches (hexyl, chafa). Front of
  # PATH in tests that need them; omitted otherwise.
  STUB="$(mktemp -d)"
  cat > "$STUB/hexyl" <<'HEXYL'
#!/usr/bin/env bash
printf 'HEXYL-DUMP-MARKER\n'
HEXYL
  chmod +x "$STUB/hexyl"
  cat > "$STUB/chafa" <<'CHAFA'
#!/usr/bin/env bash
exit 0
CHAFA
  chmod +x "$STUB/chafa"

  # ONLYBASE: symlinks to ONLY file/head/od/less - no xxd, no hexyl. xxd
  # ships in the SAME /usr/bin as file/head/od/less on macOS, so excluding
  # a directory (the /opt/homebrew/bin convention used elsewhere) cannot
  # hide it; only an allowlisted PATH does. This is the fixture that lets
  # the od-only degrade tier (both hexyl AND xxd absent) be tested for
  # real, not stubbed.
  ONLYBASE="$(mktemp -d)"
  ln -s "$(command -v file)" "$ONLYBASE/file"
  ln -s "$(command -v head)" "$ONLYBASE/head"
  ln -s "$(command -v od)" "$ONLYBASE/od"
  ln -s "$(command -v less)" "$ONLYBASE/less"

  # shellcheck disable=SC1090
  . "$LIB"
}

teardown() {
  cd /
  # Absolute path, not a PATH lookup: several tests deliberately narrow
  # PATH down to $ONLYBASE (no /bin) to prove the od-only degrade tier, and
  # that narrowed PATH is still in effect here once the test body returns.
  /bin/rm -rf "$FIX" "$STUB" "$ONLYBASE"
  # Restore a normal PATH so bats-core's OWN post-teardown bookkeeping
  # (which runs after this function, in the same process) can still find
  # its usual coreutils - a narrowed-PATH test must not poison the runner.
  export PATH="/usr/bin:/bin:$PATH"
}

# ---- match: fallback is a true always-0 catch-all ----

@test "fallback: match_render_fallback accepts a plain text file" {
  match_render_fallback "$FIX/text.md"
}

@test "fallback: match_render_fallback accepts a binary file" {
  match_render_fallback "$FIX/binary.bin"
}

@test "fallback: match_render_fallback accepts a no-extension file" {
  match_render_fallback "$FIX/noext"
}

# ---- render: hexyl present vs absent, both degrade tiers ----

@test "fallback: hexyl present -> render_fallback uses hexyl" {
  export PATH="$STUB:/usr/bin:/bin"
  run render_fallback "$FIX/binary.bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"type:"* ]]
  [[ "$output" == *"HEXYL-DUMP-MARKER"* ]]
}

@test "fallback: hexyl absent, xxd present -> render_fallback degrades to xxd and never leaks the raw escape sequence" {
  export PATH="/usr/bin:/bin"
  ! command -v hexyl >/dev/null 2>&1
  command -v xxd >/dev/null 2>&1
  run render_fallback "$FIX/binary.bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"type:"* ]]
  local esc
  esc=$'\x1b'
  [[ "$output" != *"$esc"* ]]
}

@test "fallback: hexyl AND xxd absent -> render_fallback degrades to od and never leaks the raw escape sequence" {
  export PATH="$ONLYBASE"
  ! command -v hexyl >/dev/null 2>&1
  ! command -v xxd >/dev/null 2>&1
  command -v od >/dev/null 2>&1
  run render_fallback "$FIX/binary.bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"type:"* ]]
  local esc
  esc=$'\x1b'
  [[ "$output" != *"$esc"* ]]
  # a genuine dump happened (hex-looking bytes present), not an empty body
  [[ "$output" == *"1b"* ]]
}

@test "fallback: works with zero optional tools (a no-extension binary still renders safely)" {
  export PATH="$ONLYBASE"
  run render_fallback "$FIX/noext"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no specific renderer"* ]]
  [[ "$output" == *"type:"* ]]
}

# ---- hint: correct only when a mapped tool is genuinely absent ----

@test "fallback: .png reaching fallback with chafa absent shows the install hint" {
  export PATH="/usr/bin:/bin"
  ! command -v chafa >/dev/null 2>&1
  run render_fallback "$FIX/pic.png"
  [ "$status" -eq 0 ]
  [[ "$output" == *"install chafa"* ]]
}

@test "fallback: .png reaching fallback with chafa present shows no hint" {
  export PATH="$STUB:/usr/bin:/bin"
  command -v chafa >/dev/null 2>&1
  run render_fallback "$FIX/pic.png"
  [ "$status" -eq 0 ]
  [[ "$output" != *"install chafa"* ]]
  [[ "$output" != *hint* ]]
}

@test "fallback: an unmapped extension shows no hint regardless of installed tools" {
  export PATH="$STUB:/usr/bin:/bin"
  run render_fallback "$FIX/blob.xyz"
  [ "$status" -eq 0 ]
  [[ "$output" != *hint* ]]
}

# ---- negative control: fallback is genuinely the terminal sink ----

@test "fallback: a garbage file with a markdown/image extension only routes here because every specific matcher declined" {
  export PATH="/usr/bin:/bin"
  local kind
  for kind in markdown image gif svg pdf archive csv json ipynb office media sqlite plist; do
    if "match_render_$kind" "$FIX/pic.png"; then
      echo "kind $kind unexpectedly claimed $FIX/pic.png" >&2
      return 1
    fi
  done
  match_render_fallback "$FIX/pic.png"
  run render_any "$FIX/pic.png"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no specific renderer"* ]]
}
