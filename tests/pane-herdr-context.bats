#!/usr/bin/env bats
# Viewer-gate short-circuit + herdr_bin absolute fallback.
#
# HONEST FRAMING: these were written against a theory (panes inherit the
# herdr server's minimal PATH) that was later DISPROVEN - a spawned action
# was measured with the full login PATH, and the mis-routed directory bug
# had an unrelated cause. The behaviour under test is still real and
# shipped, so the tests stay; they are defensive-fallback tests, NOT a
# regression net for an observed production failure. Do not cite them as
# evidence that panes lack PATH entries.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/adir"
  unset QUICKLOOK_VIEWER_OK HERDR_BIN_PATH QUICKLOOK_ROOTS
}

teardown() {
  cd /
  rm -rf "$FIX"
}

@test "viewer gate: QUICKLOOK_VIEWER_OK=1 routes a dir to the viewer with NO herdr reachable" {
  run env -u HERDR_BIN_PATH PATH=/usr/bin:/bin QUICKLOOK_VIEWER_OK=1 \
    bash -c ". '$LIB'; resolve_any_token '$FIX/adir' && printf 'MODE=%s' \"\$RESOLVED_MODE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=viewer"* ]]
}

@test "viewer gate: QUICKLOOK_VIEWER_OK=0 degrades a dir to the paged tree listing" {
  run env -u HERDR_BIN_PATH PATH=/usr/bin:/bin QUICKLOOK_VIEWER_OK=0 \
    bash -c ". '$LIB'; resolve_any_token '$FIX/adir' && printf 'MODE=%s' \"\$RESOLVED_MODE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=command"* ]]
}

@test "herdr_bin: resolves to an absolute binary when PATH cannot see herdr" {
  [ -x /opt/homebrew/bin/herdr ] || [ -x /usr/local/bin/herdr ] || skip "no absolute herdr install to fall back to"
  run env -u HERDR_BIN_PATH PATH=/usr/bin:/bin \
    bash -c ". '$LIB'; printf '%s' \"\$herdr_bin\""
  [ "$status" -eq 0 ]
  [[ "$output" == /* ]]
  [ -x "$output" ]
}

@test "regression: a dir with a minimal PATH still reaches viewer mode (was: popup)" {
  [ -x /opt/homebrew/bin/herdr ] || [ -x /usr/local/bin/herdr ] || skip "no absolute herdr install to fall back to"
  run env -u HERDR_BIN_PATH -u QUICKLOOK_VIEWER_OK PATH=/usr/bin:/bin \
    bash -c ". '$LIB'; resolve_any_token '$FIX/adir' && printf 'MODE=%s' \"\$RESOLVED_MODE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"MODE=viewer"* ]]
}

@test "hint action really forwards the gate answer into the overlay argv" {
  # was a source grep, which passes even if the flag never reaches herdr;
  # run the action against a stub herdr and read the argv it actually built.
  local stub hlog
  stub="$(mktemp -d)"; hlog="$(mktemp)"
  cat > "$stub/herdr" <<HERDR
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$hlog"
exit 0
HERDR
  chmod +x "$stub/herdr"
  printf '#!/usr/bin/env bash\nprintf "{}"\n' > "$stub/jq"; chmod +x "$stub/jq"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/pbpaste"; chmod +x "$stub/pbpaste"
  PATH="$stub:/usr/bin:/bin" HERDR_BIN_PATH="$stub/herdr" \
    run bash "$BATS_TEST_DIRNAME/../scripts/hint.sh"
  grep -q -- "--env QUICKLOOK_VIEWER_OK=" "$hlog"
  rm -rf "$stub"
}
