#!/usr/bin/env bats
# Tests for scripts/renderers/svg.sh (svg via rsvg-convert -> chafa, v0.4
# SG-06/P2). Same fixture/sourcing shape as tests/render-registry.bats.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>\n' > "$FIX/t.svg"
  # binary garbage wearing a .svg extension - the negative control, same
  # shape as render-registry.bats's own blob.bin.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.svg"

  STUB="$(mktemp -d)"
  export RSVG_ARGV_FILE="$FIX/rsvg.argv"
  export CHAFA_ARGV_FILE="$FIX/chafa.argv"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

_stub_rsvg_ok() {
  cat > "$STUB/rsvg-convert" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$RSVG_ARGV_FILE"
exit 0
SH
  chmod +x "$STUB/rsvg-convert"
}

_stub_rsvg_fails() {
  cat > "$STUB/rsvg-convert" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$STUB/rsvg-convert"
}

_stub_chafa() {
  cat > "$STUB/chafa" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CHAFA_ARGV_FILE"
exit 0
SH
  chmod +x "$STUB/chafa"
}

# ---- match: both tools present ----

@test "match_render_svg: matches a real .svg when rsvg-convert and chafa are present" {
  _stub_rsvg_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  match_render_svg "$FIX/t.svg"
}

@test "match_render_svg: declines a non-svg extension" {
  _stub_rsvg_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  printf 'hello\n' > "$FIX/t.md"
  ! match_render_svg "$FIX/t.md"
}

# ---- degrade: either tool absent ----

@test "match_render_svg: declines when rsvg-convert is absent (PATH excludes /opt/homebrew/bin and /usr/local/bin)" {
  _stub_chafa
  export PATH="$STUB:/usr/bin:/bin"
  ! match_render_svg "$FIX/t.svg"
}

@test "match_render_svg: declines when chafa is absent (PATH excludes /opt/homebrew/bin and /usr/local/bin)" {
  _stub_rsvg_ok
  export PATH="$STUB:/usr/bin:/bin"
  ! match_render_svg "$FIX/t.svg"
}

@test "render-registry: tools absent - a real svg falls through to the text renderer (svg is XML text, same precedent as markdown.sh's glow-absent degrade), never fallback" {
  export PATH="/usr/bin:/bin"
  run bash -c "
    . '$LIB'
    render_text() { printf 'TEXT-RENDERED:%s\n' \"\$1\"; return 0; }
    render_fallback() { printf 'FALLBACK-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.svg'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "TEXT-RENDERED:$FIX/t.svg" ]
}

# ---- negative control: type mismatch, not just extension ----

@test "match_render_svg: declines binary garbage renamed .svg (keys on type, not extension)" {
  _stub_rsvg_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  ! match_render_svg "$FIX/fake.svg"
}

@test "render-registry: binary garbage renamed .svg routes to fallback, never rsvg-convert" {
  _stub_rsvg_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.svg'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.svg" ]
  [ ! -e "$RSVG_ARGV_FILE" ]
}

# ---- render: rsvg-convert -> temp png -> render_image (reused, not duplicated) ----

@test "render_svg: converts via rsvg-convert to a temp png, then draws the SAME file via image.sh's render_image (chafa)" {
  _stub_rsvg_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_svg '$FIX/t.svg' <<<'x'"
  [ "$status" -eq 0 ]
  [ -f "$RSVG_ARGV_FILE" ]
  grep -qx -- '-o' "$RSVG_ARGV_FILE"
  grep -qx -- "$FIX/t.svg" "$RSVG_ARGV_FILE"
  tmp_png="$(grep -A1 -x -- '-o' "$RSVG_ARGV_FILE" | tail -1)"
  [[ "$tmp_png" == *.png ]]
  [ -f "$CHAFA_ARGV_FILE" ]
  grep -qx -- "$tmp_png" "$CHAFA_ARGV_FILE"
  # the temp png is cleaned up after the render, never left behind.
  [ ! -e "$tmp_png" ]
}

@test "render_svg: a conversion failure degrades to render_fallback, never a blank/crashed frame" {
  _stub_rsvg_fails
  _stub_chafa
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_svg '$FIX/t.svg'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/t.svg" ]
  [ ! -e "$CHAFA_ARGV_FILE" ]
}
