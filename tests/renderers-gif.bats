#!/usr/bin/env bats
# Tests for scripts/renderers/gif.sh (animated gifs via chafa, v0.4 SG-04).
# Sources lib.sh directly, same fixture shape as tests/render-registry.bats.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # Minimal, REAL 1x1 GIF bytes (verified via `file --mime-type` = image/gif).
  printf '\x47\x49\x46\x38\x39\x61\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x01\x4c\x00\x3b' > "$FIX/t.gif"
  # binary garbage wearing a .gif extension (same shape as
  # render-registry.bats's own blob.bin) - the negative control. Must be
  # genuinely BINARY, not text, for the same reason as renderers-image.bats.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.gif"

  STUB="$(mktemp -d)"
  export CHAFA_ARGV_FILE="$FIX/chafa.argv"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

_stub_chafa_animate_ok() {
  cat > "$STUB/chafa" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CHAFA_ARGV_FILE"
exit 0
SH
  chmod +x "$STUB/chafa"
}

# --animate is stubbed unavailable (nonzero rc) whenever it's on the argv;
# a plain still call (no --animate) still succeeds and records its argv.
_stub_chafa_animate_unavailable() {
  cat > "$STUB/chafa" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do
  [ "$a" = "--animate" ] && exit 1
done
printf '%s\n' "$@" > "$CHAFA_ARGV_FILE"
exit 0
SH
  chmod +x "$STUB/chafa"
}

# ---- match: chafa present ----

@test "match_render_gif: matches a real .gif when chafa is present" {
  _stub_chafa_animate_ok
  export PATH="$STUB:$PATH"
  match_render_gif "$FIX/t.gif"
}

@test "match_render_gif: declines a non-gif extension" {
  _stub_chafa_animate_ok
  export PATH="$STUB:$PATH"
  printf 'hello\n' > "$FIX/t.md"
  ! match_render_gif "$FIX/t.md"
}

# ---- degrade: chafa absent ----

@test "match_render_gif: declines when chafa is absent (PATH excludes /opt/homebrew/bin and /usr/local/bin)" {
  export PATH="/usr/bin:/bin"
  ! match_render_gif "$FIX/t.gif"
}

@test "render-registry: chafa absent routes a real gif to fallback via render_any" {
  export PATH="/usr/bin:/bin"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.gif'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/t.gif" ]
}

# ---- negative control: type mismatch, not just extension ----

@test "match_render_gif: declines binary garbage renamed .gif (keys on type, not extension)" {
  _stub_chafa_animate_ok
  export PATH="$STUB:$PATH"
  ! match_render_gif "$FIX/fake.gif"
}

@test "render-registry: binary garbage renamed .gif routes to fallback, never chafa" {
  _stub_chafa_animate_ok
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.gif'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.gif" ]
  [ ! -e "$CHAFA_ARGV_FILE" ]
}

# ---- render: --animate argv, bounded duration ----

@test "render_gif: calls chafa with --animate, a duration bound, and the file" {
  _stub_chafa_animate_ok
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_gif '$FIX/t.gif' <<<'x'"
  [ "$status" -eq 0 ]
  [ -f "$FIX/chafa.argv" ]
  grep -qx -- '--animate' "$FIX/chafa.argv"
  grep -qx -- '-d' "$FIX/chafa.argv"
  grep -qx -- "$FIX/t.gif" "$FIX/chafa.argv"
}

# ---- render: first-frame-still fallback when --animate is unavailable ----

@test "render_gif: falls back to a first-frame still (explicit symbols format) when --animate is unavailable" {
  _stub_chafa_animate_unavailable
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_gif '$FIX/t.gif' <<<'x'"
  [ "$status" -eq 0 ]
  [ -f "$FIX/chafa.argv" ]
  grep -qx -- '--format' "$FIX/chafa.argv"
  grep -qx -- 'symbols' "$FIX/chafa.argv"
  ! grep -qx -- '--animate' "$FIX/chafa.argv"
}
