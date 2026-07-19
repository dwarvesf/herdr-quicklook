#!/usr/bin/env bats
# Tests for scripts/renderers/json.sh (json via `jq .`, v0.4 SG-06/P2). Same
# fixture/sourcing shape as tests/render-registry.bats.
#
# GOTCHA: unlike every other tool in this pack, `jq` is ALSO installed as a
# base-system binary at /usr/bin/jq on some hosts (verified on this one) -
# a plain PATH="/usr/bin:/bin" is NOT a real absence here. The tool-absent
# tests below use a symlink-only allowlist (mirroring
# tests/renderers-fallback.bats's ONLYBASE idiom) instead.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf '{"a":1,"b":[1,2,3]}' > "$FIX/t.json"
  # binary garbage wearing a .json extension - the negative control, same
  # shape as render-registry.bats's own blob.bin.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.json"

  # NOJQ: symlinks to ONLY file/tr/less/head/od/dirname (dirname is what
  # lib.sh itself needs at source time for LIB_DIR - see its top) - no jq.
  # See the GOTCHA note above: excluding /opt/homebrew/bin and
  # /usr/local/bin is not enough on a host where jq also lives in /usr/bin.
  NOJQ="$(mktemp -d)"
  for b in file tr less head od dirname; do
    ln -s "$(command -v "$b")" "$NOJQ/$b"
  done

  STUB="$(mktemp -d)"
  export JQ_ARGV_FILE="$FIX/jq.argv"
}

teardown() {
  cd /
  # Absolute path, not a PATH lookup: the tool-absent test above narrows
  # PATH down to $NOJQ (no /bin) for the rest of this test invocation -
  # same convention as tests/renderers-fallback.bats's ONLYBASE teardown.
  /bin/rm -rf "$FIX" "$STUB" "$NOJQ"
  # Restore a normal PATH so bats-core's OWN post-teardown bookkeeping
  # (which runs after this function, in the same process) can still find
  # its usual coreutils.
  export PATH="/usr/bin:/bin:$PATH"
}

_stub_jq() {
  cat > "$STUB/jq" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$JQ_ARGV_FILE"
printf 'JQ_PRETTY\n'
exit 0
SH
  chmod +x "$STUB/jq"
}

# ---- match: jq present ----

@test "match_render_json: matches a real .json when jq is present" {
  _stub_jq
  export PATH="$STUB:$PATH"
  match_render_json "$FIX/t.json"
}

@test "match_render_json: declines a non-json extension" {
  _stub_jq
  export PATH="$STUB:$PATH"
  printf 'hello\n' > "$FIX/t.md"
  ! match_render_json "$FIX/t.md"
}

# ---- degrade: jq absent (symlink-only allowlist, see the GOTCHA note) ----

@test "match_render_json: declines when jq is absent (symlink-only allowlist, no /usr/bin or /usr/local/bin)" {
  export PATH="$NOJQ"
  ! command -v jq >/dev/null 2>&1
  ! match_render_json "$FIX/t.json"
}

@test "render-registry: jq absent - a real json falls through to the text renderer, not fallback (json is still readable as text)" {
  export PATH="$NOJQ"
  # Absolute /bin/bash, not a PATH lookup: $NOJQ does not carry bash itself
  # (only the jq-exclusion allowlist), same reasoning as the teardown fix
  # above.
  run /bin/bash -c "
    . '$LIB'
    render_text() { printf 'TEXT-RENDERED:%s\n' \"\$1\"; return 0; }
    render_fallback() { printf 'FALLBACK-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.json'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "TEXT-RENDERED:$FIX/t.json" ]
}

# ---- negative control: type mismatch, not just extension ----

@test "match_render_json: declines binary garbage renamed .json (keys on type, not extension)" {
  _stub_jq
  export PATH="$STUB:$PATH"
  ! match_render_json "$FIX/fake.json"
}

@test "render-registry: binary garbage renamed .json routes to fallback, never jq" {
  _stub_jq
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.json'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.json" ]
  [ ! -e "$JQ_ARGV_FILE" ]
}

# ---- render: pretty-print argv, paged ----

@test "render_json: calls jq . on the file and pages the output" {
  _stub_jq
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_json '$FIX/t.json'"
  [ "$status" -eq 0 ]
  [ -f "$JQ_ARGV_FILE" ]
  grep -qx -- '.' "$JQ_ARGV_FILE"
  grep -qx -- "$FIX/t.json" "$JQ_ARGV_FILE"
  [[ "$output" == *"JQ_PRETTY"* ]]
}

# ---- real jq end-to-end (no stub): a genuine pretty-print, not a stub echo ----

@test "render_json: a real minified json pretty-prints via the actual jq binary" {
  printf '{"a":1}' > "$FIX/mini.json"
  run bash -c ". '$LIB'; render_json '$FIX/mini.json'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"a": 1'* ]]
}
