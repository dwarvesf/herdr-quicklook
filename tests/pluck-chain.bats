#!/usr/bin/env bats
# Script-level tests for scripts/pluck-chain.sh: the herdr-pluck-absent
# reroute, the invoke-failure reroute, a successful pick forwarded with no
# extra keypress, and the no-selection (cancel/timeout) degrade. A stub
# `herdr` plays the "is herdr-pluck installed" probe, the pluck invoke
# itself (writing a new value into a fake clipboard file, the same side
# effect pluck's own pbcopy has), and falls through to echoing argv for any
# other invocation (including the `pick` action-invoke reroute below, so its
# argv is directly assertable without scripts/pick.sh needing to exist in
# this worktree - SG-02 owns that file); a stub `pbpaste` reads the fake
# clipboard file so no real system clipboard is touched. PATH is pinned to
# just $STUB (no /opt/homebrew/bin, no system herdr/pbpaste) so a real
# herdr-pluck or pbpaste installed on the dev machine can never leak in.

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
  exit "${PLUCK_INVOKE_EXIT:-0}"
elif [ "$1" = "notification" ]; then
  exit 0
else
  # Catch-all, including `plugin action invoke pick --plugin herdr-quicklook`
  # (the reroute): echo argv so the caller's exact invocation is assertable.
  printf '%s\n' "$@"
fi
SH
  chmod +x "$STUB/herdr"

  cat > "$STUB/pbpaste" <<SH
#!/usr/bin/env bash
cat "$CLIP_FILE"
SH
  chmod +x "$STUB/pbpaste"

  # Deliberately NOT /opt/homebrew/bin (see NOTES.md's PATH-stub gotcha):
  # keeps a real herdr-pluck-adjacent binary from ever being reachable.
  # git/awk/sleep/mktemp/cat resolve fine from /usr/bin:/bin:/usr/local/bin
  # alone; `herdr` itself is always the stub via HERDR_BIN_PATH regardless.
  PATH="$STUB:/usr/bin:/bin:/usr/local/bin"
  export PATH HERDR_BIN_PATH="$STUB/herdr" CLIP_FILE
  # Fast polling for every test; individual tests still override the
  # timeout where they need more than one iteration's worth of headroom.
  export QUICKLOOK_PLUCK_POLL_INTERVAL=0
  export QUICKLOOK_PLUCK_TIMEOUT=0.3
  unset HERDR_PLUGIN_CONTEXT_JSON HERDR_WORKSPACE_CWD PLUCK_PICK_VALUE PLUCK_INVOKE_EXIT
}

teardown() { rm -rf "$STUB"; }

@test "pluck-chain: herdr-pluck absent -> reroutes to the native pick action, no pluck invoke" {
  export PLUCK_INSTALLED_EXIT=1
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'plugin\naction\ninvoke\npick\n--plugin\nherdr-quicklook')" ]
}

@test "pluck-chain: herdr-pluck present but triggering it fails -> reroutes to the native pick action" {
  export PLUCK_INSTALLED_EXIT=0
  export PLUCK_INVOKE_EXIT=1
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'plugin\naction\ninvoke\npick\n--plugin\nherdr-quicklook')" ]
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
