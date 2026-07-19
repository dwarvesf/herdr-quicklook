#!/usr/bin/env bats
# Tests for scripts/renderers/plist.sh (v0.4 SG-07, P3 pack). Sources lib.sh
# directly, same fixture shape as tests/render-registry.bats. `plutil` is
# base-system on macOS - no stub needed for the "present" cases, only PATH
# narrowing for the "absent" (non-macOS) degrade cases.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  REAL_PLUTIL="$(command -v plutil)"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  plutil -create xml1 "$FIX/xml.plist" >/dev/null
  /usr/libexec/PlistBuddy -c 'Add :Name string Hello' "$FIX/xml.plist" >/dev/null
  plutil -convert binary1 -o "$FIX/binary.plist" "$FIX/xml.plist"
  # binary garbage wearing a .plist extension - the negative control.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.plist"
  printf 'hello\n' > "$FIX/t.txt"

  # stub `plutil` that records its argv for `-p` (render) calls but
  # DELEGATES a `-lint` call to the real binary at its absolute path
  # (REAL_PLUTIL, baked in before PATH is ever narrowed) - the match-time
  # validity decision must stay genuine, or a dumb always-succeed stub would
  # defeat this renderer's own negative control (match_render_plist, unlike
  # every other P3 matcher, actually SHELLS OUT to validate the file rather
  # than a `file --mime-type` check alone).
  STUB="$(mktemp -d)"
  cat > "$STUB/plutil" <<SH
#!/usr/bin/env bash
if [ "\$1" = "-lint" ]; then
  exec "$REAL_PLUTIL" "\$@"
fi
printf '%s\n' "\$@" > "\$PLUTIL_ARGV_FILE"
printf 'PLUTIL_DUMP\n'
exit 0
SH
  chmod +x "$STUB/plutil"
  export PLUTIL_ARGV_FILE="$FIX/plutil.argv"

  # a PATH that excludes /opt/homebrew/bin and /usr/local/bin - the
  # tool-absent convention (see tests/renderers-fallback.bats); plutil itself
  # is base-system (/usr/bin), so a "plutil absent" fixture needs the
  # ONLYBASE-style allowlist (no plutil) further below - the other names are
  # what `bash -c '. lib.sh; ...'` itself needs to source/run under a
  # narrowed PATH (dirname/tr for the renderers, bash to spawn the nested
  # `run bash -c` subshell).
  ONLYBASE="$(mktemp -d)"
  ln -s "$(command -v file)" "$ONLYBASE/file"
  ln -s "$(command -v less)" "$ONLYBASE/less"
  ln -s "$(command -v tr)" "$ONLYBASE/tr"
  ln -s "$(command -v dirname)" "$ONLYBASE/dirname"
  ln -s "$(command -v bash)" "$ONLYBASE/bash"
}

teardown() {
  cd /
  # Absolute path, not a PATH lookup: some tests narrow PATH to $ONLYBASE
  # (no /bin), and that narrowed PATH is still in effect here.
  /bin/rm -rf "$FIX" "$STUB" "$ONLYBASE"
  export PATH="/usr/bin:/bin:$PATH"
}

# ---- match: real plists, both serializations ----

@test "match_render_plist: matches a real XML plist" {
  match_render_plist "$FIX/xml.plist"
}

@test "match_render_plist: matches a real binary plist" {
  match_render_plist "$FIX/binary.plist"
}

@test "match_render_plist: declines a non-.plist extension" {
  ! match_render_plist "$FIX/t.txt"
}

# ---- degrade: plutil absent (e.g. non-macOS) ----

@test "match_render_plist: declines when plutil is absent from PATH" {
  export PATH="$ONLYBASE"
  ! command -v plutil >/dev/null 2>&1
  ! match_render_plist "$FIX/xml.plist"
}

@test "render-registry: plutil absent - an XML plist (still genuinely text) degrades to the plain-text renderer, not fallback" {
  export PATH="$ONLYBASE"
  run bash -c "
    . '$LIB'
    render_text() { printf 'TEXT:%s\n' \"\$1\"; return 0; }
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/xml.plist'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "TEXT:$FIX/xml.plist" ]
}

@test "render-registry: plutil absent - a binary plist (not text) has no readable degrade and lands on fallback" {
  export PATH="$ONLYBASE"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/binary.plist'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/binary.plist" ]
}

# ---- negative control: binary garbage renamed .plist, keyed on plutil -lint ----

@test "match_render_plist: declines binary garbage renamed .plist (plutil -lint rejects it)" {
  ! match_render_plist "$FIX/fake.plist"
}

@test "render-registry: binary garbage renamed .plist routes to fallback, never plutil -p" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.plist'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.plist" ]
  [ ! -e "$PLUTIL_ARGV_FILE" ]
}

# ---- render: plutil -p, paged ----

@test "render_plist: calls plutil -p on the file and pages it" {
  export PATH="$STUB:$PATH"
  run render_plist "$FIX/xml.plist"
  [ "$status" -eq 0 ]
  [ -f "$PLUTIL_ARGV_FILE" ]
  grep -qx -- '-p' "$PLUTIL_ARGV_FILE"
  grep -qx -- "$FIX/xml.plist" "$PLUTIL_ARGV_FILE"
  [[ "$output" == *"PLUTIL_DUMP"* ]]
}

@test "render_plist: on a real plist shows the actual structured dump" {
  run render_plist "$FIX/xml.plist"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello"* ]]
}
