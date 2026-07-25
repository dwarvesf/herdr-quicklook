#!/usr/bin/env bats
# Pane-context contract: a plugin pane/action is spawned by the herdr server,
# which commonly has a MINIMAL PATH (measured on macOS: /usr/bin:/bin:
# /usr/sbin:/sbin). A bare `herdr` is therefore not reachable there, and a
# silently-failing herdr call downgrades a DIRECTORY token from the real file
# viewer to a tree listing in the popup. Two independent guards are pinned
# here: lib.sh resolves herdr_bin to an absolute fallback, and the
# QUICKLOOK_VIEWER_OK hint (passed by the hint action) short-circuits the
# gate's RPC entirely.

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

@test "hint action passes the gate answer into the overlay pane" {
  grep -q 'QUICKLOOK_VIEWER_OK=\$viewer_ok' "$BATS_TEST_DIRNAME/../scripts/hint.sh"
}
