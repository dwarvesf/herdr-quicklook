#!/usr/bin/env bats
# Tests for the render-registry dispatch (scripts/lib.sh render_any +
# scripts/renderers/*.sh). Sources lib.sh directly, same fixture shape as
# tests/registry.bats (the handler-registry's own test file).

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  RENDERERS_DIR="$BATS_TEST_DIRNAME/../scripts/renderers"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf 'hello world\nline two\n' > "$FIX/text.md"
  # a real binary file (null + high bytes) so file(1) reports mime-encoding
  # "binary", not a text encoding - see match_render_text/match_render_fallback.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/blob.bin"
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# ---- text/fallback real bodies (the only two non-stub renderers) ----

@test "render-registry: text renderer matches a text file" {
  match_render_text "$FIX/text.md"
}

@test "render-registry: fallback renderer matches a binary file (text declines it)" {
  ! match_render_text "$FIX/blob.bin"
  match_render_fallback "$FIX/blob.bin"
}

@test "render-registry: fallback always matches, even a plain text file" {
  # fallback is the always-0 catch-all; RENDER_KINDS ordering (text before
  # fallback), not fallback's own predicate, is what keeps it from shadowing
  # text - see the ordering test below.
  match_render_fallback "$FIX/text.md"
}

# ---- an unmatched-by-specific-kind file falls through to text/fallback ----

@test "render-registry: every declining stub actually declines a plain text file (proves the fallthrough is real, not a no-op chain)" {
  local kind
  for kind in markdown image gif svg pdf archive csv json ipynb office media sqlite plist; do
    if "match_render_$kind" "$FIX/text.md"; then
      echo "kind $kind unexpectedly claimed a plain text file" >&2
      return 1
    fi
  done
}

@test "render-registry: render_any dispatches a plain text file to the text renderer" {
  # render_text itself execs less (the real TTY-driving body) - overridden
  # here to a plain marker so this test exercises render_any's DISPATCH
  # decision, not the pager.
  run bash -c "
    . '$LIB'
    render_text() { printf 'TEXT-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/text.md'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "TEXT-RENDERED:$FIX/text.md" ]
}

@test "render-registry: render_any dispatches a binary file to the fallback renderer" {
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/blob.bin'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK-RENDERED:$FIX/blob.bin" ]
}

@test "render-registry: the real fallback renderer never dumps raw bytes, only a file(1) type line" {
  run bash -c ". '$LIB'; render_fallback '$FIX/blob.bin' <<<'x'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no specific renderer"* ]]
  [[ "$output" == *"type:"* ]]
  # blob.bin's raw bytes spell the ASCII substring "binary" on purpose (see
  # setup); if render_fallback ever `cat`'d the file instead of describing
  # it, that literal substring would leak into the output. A short,
  # line-bounded summary (never a byte-for-byte dump) is the point.
  [[ "$output" != *"binary"* ]]
  [ "$(printf '%s\n' "$output" | wc -l)" -le 4 ]
}

# ---- a registered renderer wins / first-match ordering ----

@test "render-registry: a registered renderer wins over every later kind (including fallback)" {
  match_render_zzz() { return 0; }
  render_zzz() { printf 'ZZZ-RENDERED:%s\n' "$1"; return 0; }
  RENDER_KINDS=(zzz "${RENDER_KINDS[@]}")

  run render_any "$FIX/text.md"
  [ "$status" -eq 0 ]
  [ "$output" = "ZZZ-RENDERED:$FIX/text.md" ]
}

@test "render-registry: first-match ordering - position decides, not the target's real type" {
  # zzz claims EVERYTHING; since it is FIRST in RENDER_KINDS it must win even
  # for a target (a binary file) that would otherwise resolve to fallback.
  match_render_zzz() { return 0; }
  render_zzz() { printf 'ZZZ\n'; return 0; }
  RENDER_KINDS=(zzz "${RENDER_KINDS[@]}")

  run render_any "$FIX/blob.bin"
  [ "$status" -eq 0 ]
  [ "$output" = "ZZZ" ]
}

# ---- contract-compliance: every renderer exports match_render_<kind> + render_<kind> ----

@test "render-registry: every scripts/renderers/*.sh exports match_render_<kind> and render_<kind>" {
  local f kind
  for f in "$RENDERERS_DIR"/*.sh; do
    kind="$(basename "$f" .sh)"
    kind="${kind//-/_}"
    declare -F "match_render_$kind" >/dev/null || {
      echo "missing match_render_$kind in $f" >&2
      return 1
    }
    declare -F "render_$kind" >/dev/null || {
      echo "missing render_$kind in $f" >&2
      return 1
    }
  done
}

@test "render-registry: RENDER_KINDS has fallback last and text second-to-last" {
  local n="${#RENDER_KINDS[@]}"
  [ "${RENDER_KINDS[$((n - 1))]}" = "fallback" ]
  [ "${RENDER_KINDS[$((n - 2))]}" = "text" ]
}

@test "render-registry: RENDER_KINDS pre-registers the full v0.4 roster" {
  local expected="markdown image gif svg pdf archive csv json ipynb office media sqlite plist text fallback"
  [ "${RENDER_KINDS[*]}" = "$expected" ]
}
