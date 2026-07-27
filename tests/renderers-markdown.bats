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
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" == *"-R"* ]]
}

@test "render_markdown: table rules on (default) - the source is filtered into glow's stdin" {
  stub_with_glow
  run render_markdown "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOW_ARGS:"*" -"* ]]
  [[ "$output" != *"$FIX/doc.md"* ]]
}

@test "render_markdown: QUICKLOOK_TABLE_RULES=0 hands glow the file directly" {
  stub_with_glow
  QUICKLOOK_TABLE_RULES=0 run render_markdown "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$FIX/doc.md"* ]]
}

@test "render_markdown: the line arg is accepted but ignored (best-effort, no error)" {
  stub_with_glow
  run render_markdown "$FIX/doc.md" 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOW_ARGS:"* ]]
}

@test "render_markdown: QUICKLOOK_GLOW_STYLE overrides the glow style" {
  stub_with_glow
  QUICKLOOK_GLOW_STYLE=dracula run render_markdown "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s dracula"* ]]
}

@test "render_markdown: picks up herdr-file-viewer's bundled palette when installed" {
  stub_with_glow
  # fake herdr + jq answering the plugin-root lookup, and a palette file at
  # the viewer's documented asset path.
  mkdir -p "$STUB/vroot/assets"
  printf '{}' > "$STUB/vroot/assets/markdown-style.json"
  cat > "$STUB/herdr" <<'SH'
#!/usr/bin/env bash
printf '{}'
SH
  cat > "$STUB/jq" <<SH
#!/usr/bin/env bash
printf '%s\n' "$STUB/vroot"
SH
  chmod +x "$STUB/herdr" "$STUB/jq"
  unset QUICKLOOK_GLOW_STYLE HERDR_BIN_PATH
  # linkify off: this asserts what glow was INVOKED with, and the linkifier
  # legitimately wraps the style path in an OSC-8 link on the way to the
  # pager, which splits the literal "-s <path>" run.
  QUICKLOOK_LINKIFY=0 run render_markdown "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s $STUB/vroot/assets/markdown-style.json"* ]]
}

@test "render_markdown: no viewer installed falls back to -s auto" {
  stub_with_glow
  unset QUICKLOOK_GLOW_STYLE HERDR_BIN_PATH
  run render_markdown "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s auto"* ]]
}

@test "render_markdown: always passes an explicit -w width to glow" {
  stub_with_glow
  run render_markdown "$FIX/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" =~ -w\ [0-9]+ ]]
}

# The pre-fix bug: `tput cols` reads the size off STDOUT, and render_markdown
# measures inside a command substitution (a pipe), so glow got a hard -w 80 in
# a 200-column pane. pane_cols reads /dev/tty instead, minus the pad_left
# gutter, so glow's full-width rows do not then overflow and soft-wrap.
@test "render_markdown: -w carries the measured pane width minus the gutter" {
  stub_with_glow
  run bash -c ". '$LIB'; _pane_cols() { printf '132'; }; render_markdown '$FIX/doc.md'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-w 130"* ]]
}

@test "render_markdown: an unmeasurable width floors at 80, never 0" {
  stub_with_glow
  run bash -c ". '$LIB'; _pane_cols() { printf '0'; }; render_markdown '$FIX/doc.md'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-w 80"* ]]
}

@test "_pane_cols is silent and numeric with no controlling tty" {
  run bash -c ". '$LIB'; unset COLUMNS; _pane_cols" < /dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ---- table row rules (glamour draws no per-row rule of its own) ----

@test "_md_table_spacers: inserts a marker row between data rows, never before the first" {
  printf '| A | B |\n|---|---|\n| one | two |\n| three | four |\n' > "$FIX/tbl.md"
  run _md_table_spacers < "$FIX/tbl.md"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'qlhr')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | sed -n '4p')" = "|⟦qlhr⟧||" ]
}

@test "_md_table_spacers: leaves a table inside a fenced code block alone" {
  printf '```\n| A | B |\n|---|---|\n| one | two |\n| three | four |\n```\n' > "$FIX/fenced.md"
  run _md_table_spacers < "$FIX/fenced.md"
  [ "$status" -eq 0 ]
  [[ "$output" != *qlhr* ]]
}

@test "_md_table_rules: replaces the marker line with that table's own header rule" {
  run bash -c ". '$LIB'; printf ' A   \xe2\x94\x82 B\n\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80\xe2\x94\xbc\xe2\x94\x80\xe2\x94\x80\n one \xe2\x94\x82 two\n \xe2\x9f\xa6qlhr\xe2\x9f\xa7 \xe2\x94\x82\n x   \xe2\x94\x82 y\n' | _md_table_rules"
  [ "$status" -eq 0 ]
  [[ "$output" != *qlhr* ]]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" = "$(printf '%s\n' "$output" | sed -n '4p')" ]
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
