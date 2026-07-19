#!/usr/bin/env bats
# Tests for scripts/renderers/ipynb.sh (v0.4 SG-07, P3 pack): pandoc's ipynb
# reader -> div-fence-stripped markdown -> render_markdown (SG-03, reused by
# calling). Sources lib.sh directly, same fixture shape as
# tests/render-registry.bats.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  cat > "$FIX/t.ipynb" <<'JSON'
{
 "cells": [
  {"cell_type": "markdown", "metadata": {}, "source": ["# Title\n", "\n", "Some **text**."]},
  {"cell_type": "code", "metadata": {}, "execution_count": 1, "outputs": [], "source": ["print('hello')\n", "x = 1 + 1"]}
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
  "language_info": {"name": "python", "version": "3.11"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
JSON
  # syntactically-invalid JSON, still genuinely TEXT (valid UTF-8) - matches
  # ipynb (it IS text) but pandoc will fail to parse it; render_ipynb must
  # degrade to a graceful in-pager notice, never a crash.
  printf '{not valid json' > "$FIX/broken.ipynb"
  # binary garbage wearing a .ipynb extension - the negative control.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.ipynb"
  printf 'plain text\n' > "$FIX/t.txt"

  STUB="$(mktemp -d)"
  cat > "$STUB/glow" <<'SH'
#!/usr/bin/env bash
printf 'GLOW_ARGS:%s\n' "$*"
cat "${@: -1}"
SH
  cat > "$STUB/less" <<'SH'
#!/usr/bin/env bash
printf 'LESS_ARGS:%s\n' "$*"
cat
SH
  chmod +x "$STUB/glow" "$STUB/less"

  ONLYBASE="$(mktemp -d)"
  ln -s "$(command -v file)" "$ONLYBASE/file"
  ln -s "$(command -v tr)" "$ONLYBASE/tr"
  ln -s "$(command -v dirname)" "$ONLYBASE/dirname"
  ln -s "$(command -v bash)" "$ONLYBASE/bash"
  ln -s "$(command -v mktemp)" "$ONLYBASE/mktemp"
  ln -s "$(command -v sed)" "$ONLYBASE/sed"
  ln -s "$(command -v rm)" "$ONLYBASE/rm"
}

teardown() {
  cd /
  /bin/rm -rf "$FIX" "$STUB" "$ONLYBASE"
  export PATH="/usr/bin:/bin:$PATH"
}

# ---- match: pandoc + glow present ----

@test "match_render_ipynb: matches a real notebook when pandoc and glow are on PATH" {
  export PATH="$STUB:$PATH"
  match_render_ipynb "$FIX/t.ipynb"
}

@test "match_render_ipynb: declines a non-.ipynb extension" {
  export PATH="$STUB:$PATH"
  ! match_render_ipynb "$FIX/t.txt"
}

# ---- degrade: pandoc or glow absent ----

@test "match_render_ipynb: declines when pandoc is absent from PATH" {
  GLOWONLY="$(mktemp -d)"
  ln -s "$STUB/glow" "$GLOWONLY/glow"
  export PATH="$GLOWONLY:$ONLYBASE"
  ! command -v pandoc >/dev/null 2>&1
  ! match_render_ipynb "$FIX/t.ipynb"
  /bin/rm -rf "$GLOWONLY"
}

@test "match_render_ipynb: declines when glow is absent from PATH" {
  PANDOCONLY="$(mktemp -d)"
  ln -s "$(command -v pandoc)" "$PANDOCONLY/pandoc"
  export PATH="$PANDOCONLY:$ONLYBASE"
  ! command -v glow >/dev/null 2>&1
  ! match_render_ipynb "$FIX/t.ipynb"
  /bin/rm -rf "$PANDOCONLY"
}

@test "render-registry: pandoc absent - a real notebook (still genuinely text/JSON) degrades to the plain-text renderer" {
  GLOWONLY="$(mktemp -d)"
  ln -s "$STUB/glow" "$GLOWONLY/glow"
  export PATH="$GLOWONLY:$ONLYBASE"
  run bash -c "
    . '$LIB'
    render_text() { printf 'TEXT:%s\n' \"\$1\"; return 0; }
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.ipynb'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "TEXT:$FIX/t.ipynb" ]
  /bin/rm -rf "$GLOWONLY"
}

# ---- negative control: binary garbage renamed .ipynb ----

@test "match_render_ipynb: declines binary garbage renamed .ipynb (keys on encoding, not extension)" {
  export PATH="$STUB:$PATH"
  ! match_render_ipynb "$FIX/fake.ipynb"
}

@test "render-registry: binary garbage renamed .ipynb routes to fallback, never pandoc/glow" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.ipynb'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.ipynb" ]
}

# ---- render: real conversion reuses render_markdown ----

@test "render_ipynb: converts cells to markdown and dispatches through render_markdown" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_markdown() { printf 'MARKDOWN-RENDERED:%s\n' \"\$(cat \"\$1\")\"; return 0; }
    render_ipynb '$FIX/t.ipynb'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"MARKDOWN-RENDERED:"* ]]
  [[ "$output" == *"# Title"* ]]
  [[ "$output" == *"print('hello')"* ]]
  # pandoc's own div-fence wrapper must be stripped before glow ever sees it.
  [[ "$output" != *':::'* ]]
}

@test "render_ipynb: end to end (real pandoc+glow stub) shows the notebook's markdown and code cell" {
  export PATH="$STUB:$PATH"
  run render_ipynb "$FIX/t.ipynb"
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Title"* ]]
  [[ "$output" == *"print('hello')"* ]]
}

@test "render_ipynb: a syntactically-broken notebook degrades to a graceful notice, never a crash" {
  export PATH="$STUB:$PATH"
  run render_ipynb "$FIX/broken.ipynb"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not convert"* ]]
}
