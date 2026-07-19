#!/usr/bin/env bats
# Tests for the markdown render-registry renderer (SG-03): scripts/renderers/
# markdown.sh's match_render_markdown/render_markdown, plus render_any
# dispatch through it. Same fixture/sourcing shape as tests/render-registry.
# bats (sources lib.sh directly).

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf '# Hello\n\nSome **bold** text.\n' > "$FIX/doc.md"
  printf '# Hello\n\nSame content, .markdown extension.\n' > "$FIX/doc.markdown"
  printf 'plain text, not a markdown extension\n' > "$FIX/doc.txt"
  # binary garbage wearing a .md extension - the negative control: extension
  # alone must not be enough, file(1) has to say "binary" to decline it.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/blob.md"
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# stub dir with a fake glow + less, PATH built WITHOUT /opt/homebrew/bin or
# /usr/local/bin (this host has a REAL glow in both - see the PATH-stub
# gotcha called out in recents.bats; leaking the real one would defeat the
# glow-absent tests further down and make render's argv assertions brittle
# against whatever glow happens to print).
stub_with_glow() {
  STUB="$(mktemp -d)"
  cat > "$STUB/glow" <<'SH'
#!/usr/bin/env bash
printf 'GLOW_ARGS:%s\n' "$*"
SH
  cat > "$STUB/less" <<'SH'
#!/usr/bin/env bash
printf 'LESS_ARGS:%s\n' "$*"
cat
SH
  chmod +x "$STUB/glow" "$STUB/less"
  export PATH="$STUB:/usr/bin:/bin"
}

# same stub dir, minus glow - the tool-absent degrade path.
stub_without_glow() {
  STUB="$(mktemp -d)"
  cat > "$STUB/less" <<'SH'
#!/usr/bin/env bash
printf 'LESS_ARGS:%s\n' "$*"
cat
SH
  chmod +x "$STUB/less"
  export PATH="$STUB:/usr/bin:/bin"
}

# ---- match_render_markdown ----

@test "match_render_markdown: matches a .md file when glow is on PATH" {
  stub_with_glow
  match_render_markdown "$FIX/doc.md"
}

@test "match_render_markdown: matches a .markdown file when glow is on PATH" {
  stub_with_glow
  match_render_markdown "$FIX/doc.markdown"
}

@test "match_render_markdown: declines when glow is absent from PATH" {
  stub_without_glow
  ! match_render_markdown "$FIX/doc.md"
}

@test "match_render_markdown: declines a non-markdown extension even with glow present" {
  stub_with_glow
  ! match_render_markdown "$FIX/doc.txt"
}

@test "match_render_markdown: declines binary-garbage content despite a .md extension (keys on type, not just extension)" {
  stub_with_glow
  ! match_render_markdown "$FIX/blob.md"
}

# ---- render_markdown: pages glow's output through less ----

@test "render_markdown: pipes glow's rendered output through less -R" {
  stub_with_glow
  run render_markdown "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOW_ARGS:"* ]]
  [[ "$output" == *"-s auto"* ]]
  [[ "$output" == *"$FIX/doc.md"* ]]
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" == *"-R"* ]]
}

@test "render_markdown: the line arg is accepted but ignored (best-effort, no error)" {
  stub_with_glow
  run render_markdown "$FIX/doc.md" 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOW_ARGS:"* ]]
}

# ---- render_any dispatch: glow-present renders, glow-absent degrades ----

@test "render_any: glow present - a .md file dispatches to the markdown renderer" {
  stub_with_glow
  run bash -c "
    . '$LIB'
    render_markdown() { printf 'MARKDOWN-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/doc.md'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "MARKDOWN-RENDERED:$FIX/doc.md" ]
}

@test "render_any: glow absent - a .md file falls through to the text renderer, not fallback" {
  stub_without_glow
  run bash -c "
    . '$LIB'
    render_text() { printf 'TEXT-RENDERED:%s\n' \"\$1\"; return 0; }
    render_fallback() { printf 'FALLBACK-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/doc.md'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "TEXT-RENDERED:$FIX/doc.md" ]
}

# ---- negative control: binary garbage in a .md wrapper never reaches glow ----

@test "render_any: binary-garbage file with a .md extension resolves to fallback, never glow-rendered as markdown" {
  stub_with_glow
  run bash -c "
    . '$LIB'
    render_markdown() { printf 'MARKDOWN-RENDERED:%s\n' \"\$1\"; return 0; }
    render_text() { printf 'TEXT-RENDERED:%s\n' \"\$1\"; return 0; }
    render_fallback() { printf 'FALLBACK-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/blob.md'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK-RENDERED:$FIX/blob.md" ]
}
