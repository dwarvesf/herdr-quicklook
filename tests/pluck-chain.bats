#!/usr/bin/env bats
# Script-level tests for scripts/pluck-chain.sh: the herdr-pluck-absent
# fallback, a successful pick forwarded with no extra keypress, and the
# no-selection (cancel/timeout) degrade. A stub `herdr` plays both the
# "is herdr-pluck installed" probe and the pick itself (writing a new value
# into a fake clipboard file, the same side effect pluck's own pbcopy has);
# a stub `pbpaste` reads that file so no real system clipboard is touched.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/pluck-chain.sh"
  STUB="$(mktemp -d)"
  CLIP_FILE="$STUB/clip.txt"
  printf 'before-value' > "$CLIP_FILE"

  cat > "$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "plugin" ] && [ "$2" = "action" ] && [ "$3" = "list" ]; then
  exit "${PLUCK_INSTALLED_EXIT:-0}"
elif [ "$1" = "plugin" ] && [ "$2" = "action" ] && [ "$3" = "invoke" ] && [ "$4" = "pluck" ]; then
  # Side effect only, mirrors herdr-pluck's own pbcopy on a real pick;
  # PLUCK_PICK_VALUE unset means the user cancelled (clipboard untouched).
  if [ -n "${PLUCK_PICK_VALUE+x}" ]; then
    printf '%s' "$PLUCK_PICK_VALUE" > "$CLIP_FILE"
  fi
  exit 0
elif [ "$1" = "notification" ]; then
  exit 0
else
  printf '%s\n' "$@"
fi
SH
  chmod +x "$STUB/herdr"

  cat > "$STUB/pbpaste" <<SH
#!/usr/bin/env bash
cat "$CLIP_FILE"
SH
  chmod +x "$STUB/pbpaste"

  PATH="$STUB:$PATH"
  export PATH HERDR_BIN_PATH="$STUB/herdr" CLIP_FILE
  # Fast polling for every test; individual tests still override the
  # timeout where they need more than one iteration's worth of headroom.
  export QUICKLOOK_PLUCK_POLL_INTERVAL=0
  export QUICKLOOK_PLUCK_TIMEOUT=0.3
  unset HERDR_PLUGIN_CONTEXT_JSON HERDR_WORKSPACE_CWD PLUCK_PICK_VALUE
}

teardown() { rm -rf "$STUB"; }

@test "pluck-chain: herdr-pluck absent -> degrades to the plain clipboard flow, no pluck invoke" {
  export PLUCK_INSTALLED_EXIT=1
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- 'pane' <<<"$output"
  ! grep -q -- '--env' <<<"$output"
}

@test "pluck-chain: a pick lands on the clipboard -> forwarded to the preview overlay, no extra keypress" {
  export PLUCK_INSTALLED_EXIT=0
  export PLUCK_PICK_VALUE="src/x.go:42"
  export QUICKLOOK_PLUCK_TIMEOUT=1
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- '--env' <<<"$output"
  grep -qx 'QUICKLOOK_TOKEN=src/x.go:42' <<<"$output"
}

@test "pluck-chain: no selection within the timeout -> notifies, opens nothing" {
  export PLUCK_INSTALLED_EXIT=0
  # PLUCK_PICK_VALUE stays unset: the stub's clipboard side effect never
  # fires, so the poll never sees a change.
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
