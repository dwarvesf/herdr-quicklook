#!/usr/bin/env bats
# Tests for scripts/renderers/image.sh (still images via chafa, v0.4 SG-04).
# Sources lib.sh directly, same fixture shape as tests/render-registry.bats.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # Minimal, REAL 1x1 PNG bytes (verified via `file --mime-type` = image/png).
  printf '\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x04\x00\x00\x00\xb5\x1c\x0c\x02\x00\x00\x00\x0b\x49\x44\x41\x54\x78\xda\x63\x64\xf8\x0f\x00\x01\x05\x01\x01\x27\x18\xe3\x66\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82' > "$FIX/t.png"
  cp "$FIX/t.png" "$FIX/t.jpg"
  cp "$FIX/t.png" "$FIX/t.jpeg"
  cp "$FIX/t.png" "$FIX/t.webp"
  cp "$FIX/t.png" "$FIX/t.bmp"
  # binary garbage wearing an image extension (null + high bytes, same shape
  # as render-registry.bats's own blob.bin) - the negative control. Must be
  # genuinely BINARY, not text: a text file here would legitimately match
  # the `text` renderer (which keys on mime-ENCODING, not extension) and
  # this test would be asserting the wrong thing.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.png"

  # a stub chafa that records its argv (order preserved) so render tests can
  # assert the invocation shape without needing a real terminal.
  STUB="$(mktemp -d)"
  cat > "$STUB/chafa" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CHAFA_ARGV_FILE"
exit 0
SH
  chmod +x "$STUB/chafa"
  export CHAFA_ARGV_FILE="$FIX/chafa.argv"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

# ---- match: chafa present ----

@test "match_render_image: matches every still extension when chafa is present" {
  export PATH="$STUB:$PATH"
  match_render_image "$FIX/t.png"
  match_render_image "$FIX/t.jpg"
  match_render_image "$FIX/t.jpeg"
  match_render_image "$FIX/t.webp"
  match_render_image "$FIX/t.bmp"
}

@test "match_render_image: declines a non-image extension" {
  export PATH="$STUB:$PATH"
  printf 'hello\n' > "$FIX/t.md"
  ! match_render_image "$FIX/t.md"
}

# ---- degrade: chafa absent ----

@test "match_render_image: declines when chafa is absent (PATH excludes /opt/homebrew/bin and /usr/local/bin)" {
  export PATH="/usr/bin:/bin"
  ! match_render_image "$FIX/t.png"
}

@test "render-registry: chafa absent routes a real image to fallback via render_any" {
  export PATH="/usr/bin:/bin"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.png'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/t.png" ]
}

# ---- negative control: type mismatch, not just extension ----

@test "match_render_image: declines binary garbage renamed .png (keys on type, not extension)" {
  export PATH="$STUB:$PATH"
  ! match_render_image "$FIX/fake.png"
}

@test "render-registry: binary garbage renamed .png routes to fallback, never chafa" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.png'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.png" ]
  [ ! -e "$CHAFA_ARGV_FILE" ]
}

# ---- render: ANSI base path argv + pause ----

@test "render_image: base path calls chafa with the file and an explicit symbols/format flag, then pauses" {
  export PATH="$STUB:$PATH"
  unset KITTY_WINDOW_ID
  export TERM=xterm
  run bash -c ". '$LIB'; render_image '$FIX/t.png' <<<'x'"
  [ "$status" -eq 0 ]
  [ -f "$FIX/chafa.argv" ]
  grep -qx -- '--format' "$FIX/chafa.argv"
  grep -qx -- 'symbols' "$FIX/chafa.argv"
  grep -qx -- "$FIX/t.png" "$FIX/chafa.argv"
}

@test "render_image: a kitty-capable env still produces a valid render (enhancement path does not break)" {
  export PATH="$STUB:$PATH"
  export KITTY_WINDOW_ID=1
  run bash -c ". '$LIB'; render_image '$FIX/t.png' <<<'x'"
  [ "$status" -eq 0 ]
  [ -f "$FIX/chafa.argv" ]
  grep -qx -- "$FIX/t.png" "$FIX/chafa.argv"
  # the enhancement branch omits --format, letting chafa auto-detect.
  ! grep -qx -- '--format' "$FIX/chafa.argv"
}
