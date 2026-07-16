#!/usr/bin/env bats
# Script-level tests for open-preview.sh's argument forwarding. A stub `herdr`
# on PATH captures the argv the script would exec, so we assert on the flags
# without a running server. Covers the SPEC-001 TASK-004 acceptance directly
# (the review CRITICAL lived exactly here: $1 clobbered by `set --`).

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/open-preview.sh"
  STUB="$(mktemp -d)"
  cat > "$STUB/herdr" <<'SH'
#!/usr/bin/env bash
# echo the full argv, one per line, so tests can grep it
printf '%s\n' "$@"
SH
  chmod +x "$STUB/herdr"
  PATH="$STUB:$PATH"
  export PATH
  # no herdr context; the script falls back cleanly
  unset HERDR_PLUGIN_CONTEXT_JSON HERDR_WORKSPACE_CWD
}

teardown() { rm -rf "$STUB"; }

@test "open-preview: no arg emits NO --env flag" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q -- '--env' <<<"$output"
  # sanity: it still built the pane-open command
  grep -q -- 'pane' <<<"$output"
}

@test "open-preview: a token arg is forwarded verbatim as QUICKLOOK_TOKEN" {
  run bash "$SCRIPT" "src/x.go:42"
  [ "$status" -eq 0 ]
  grep -q -- '--env' <<<"$output"
  grep -qx 'QUICKLOOK_TOKEN=src/x.go:42' <<<"$output"
}

@test "open-preview: never forwards the literal 'plugin' (the set-- clobber bug)" {
  run bash "$SCRIPT"
  ! grep -qx 'QUICKLOOK_TOKEN=plugin' <<<"$output"
}
