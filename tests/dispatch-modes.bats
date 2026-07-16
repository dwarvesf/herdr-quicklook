#!/usr/bin/env bats
# Script-level tests for the RESOLVED_MODE=command / RESOLVED_MODE=viewer
# dispatch arms in preview-pane.sh and open-in-viewer.sh (added after the
# kit:advisor CRITICAL on PR #7: a mode-unaware pane script would either
# reject a valid command-mode result on its empty RESOLVED_TARGET, or fall
# through to `exec less <directory>` for a viewer-mode result). No real
# handler emits `command` yet (vcs.sh is still a stub); dir.sh (SG-04) emits
# `viewer`/`command` for real now, see tests/handlers-dir.bats for its own
# coverage. This file still drops a TEMPORARY test-only handler into the real
# scripts/handlers/ directory
# for the duration of each test (glob-discovered by lib.sh at source time,
# same as any real handler) and removes it in teardown , the only way to
# exercise the full pane-script dispatch as a fresh process, same style as
# dispatch.bats.

setup() {
  PREVIEW="$BATS_TEST_DIRNAME/../scripts/preview-pane.sh"
  VIEWER="$BATS_TEST_DIRNAME/../scripts/open-in-viewer.sh"
  HANDLERS_DIR="$BATS_TEST_DIRNAME/../scripts/handlers"
  TEST_HANDLER="$HANDLERS_DIR/zzz-test-only.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/myrepo/somedir"
  git -C "$FIX/myrepo" init -q -b main
  printf 'line1\n' > "$FIX/myrepo/f.md"
  git -C "$FIX/myrepo" add -A
  git -C "$FIX/myrepo" -c user.email=t@t -c user.name=t commit -qm fix

  MARKER="$(mktemp)"

  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS: %%s\\n" "$*"\n' > "$STUB/less"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/herdr"
  chmod +x "$STUB/less" "$STUB/herdr"

  cd "$FIX/myrepo"
  export PATH="$STUB:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS
  bat() { return 127; }
  export -f bat 2>/dev/null || true

  # a test-only handler kind, claimed via QUICKLOOK_TOKEN token names below.
  # match_zzz_test_only intentionally does NOT get added to HANDLER_KINDS
  # (that array is a fixed literal in lib.sh, not test-mutable from outside
  # the sourcing process) - instead it's globbed in automatically by the
  # `for _herdr_handler in "$LIB_DIR"/handlers/*.sh` loop, same as any real
  # handler file, and it self-registers into HANDLER_KINDS at source time.
  cat > "$TEST_HANDLER" <<HANDLER
# shellcheck shell=bash
# shellcheck disable=SC2034
match_zzz_test_only() {
  case "\$1" in
    TEST_CMD_TOKEN|TEST_CMD_EMPTY_TOKEN|TEST_VIEWER_TOKEN) return 0 ;;
    *) return 1 ;;
  esac
}
handle_zzz_test_only() {
  case "\$1" in
    TEST_CMD_TOKEN)
      RESOLVED_MODE="command"
      RESOLVED_CMD=(bash -c 'printf "%s\n" "\$@" > "$MARKER"' -- "one" "two words" "three")
      return 0
      ;;
    TEST_CMD_EMPTY_TOKEN)
      RESOLVED_MODE="command"
      RESOLVED_CMD=()
      return 0
      ;;
    TEST_VIEWER_TOKEN)
      RESOLVED_MODE="viewer"
      RESOLVED_TARGET="$FIX/myrepo/somedir"
      return 0
      ;;
  esac
  return 1
}
# HANDLER_KINDS is a literal array already set by the time this file is
# sourced (lib.sh builds it, THEN globs scripts/handlers/*.sh); prepend so
# this test kind gets first look, same mechanism registry.bats already
# exercises ("a higher-priority handler always wins").
HANDLER_KINDS=(zzz_test_only "\${HANDLER_KINDS[@]}")
HANDLER
}

teardown() {
  cd /
  rm -f "$TEST_HANDLER"
  rm -f "$MARKER"
  rm -rf "$FIX" "$STUB"
}

# ---- preview-pane.sh: command mode ----

@test "preview-pane command mode: runs the argv, each element stays one token" {
  export QUICKLOOK_TOKEN="TEST_CMD_TOKEN"
  run bash "$PREVIEW"
  [ "$status" -eq 0 ]
  # the argv ran (marker file was written) with each element intact,
  # including the one with an embedded space, proving no re-splitting.
  run cat "$MARKER"
  [ "${lines[0]}" = "one" ]
  [ "${lines[1]}" = "two words" ]
  [ "${lines[2]}" = "three" ]
}

@test "preview-pane command mode: output is paged (less invoked, not exec'd on a path)" {
  export QUICKLOOK_TOKEN="TEST_CMD_TOKEN"
  run bash "$PREVIEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"* ]]
  # command-mode output is piped into less's stdin, never appended as a
  # trailing positional arg (that would mean the OLD file-render path ran).
  [[ "$output" != *"LESS_ARGS:"*"$FIX"* ]]
}

@test "preview-pane command mode: empty RESOLVED_CMD does not hit the not-found guard as a crash, falls through cleanly" {
  export QUICKLOOK_TOKEN="TEST_CMD_EMPTY_TOKEN"
  run bash "$PREVIEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a file I can find"* ]]
}

# ---- preview-pane.sh: viewer mode ----

@test "preview-pane viewer mode: never reaches exec less on the directory" {
  export QUICKLOOK_TOKEN="TEST_VIEWER_TOKEN"
  run bash "$PREVIEW"
  [ "$status" -eq 0 ]
  # less WAS invoked (the safe tree-listing degrade pages through it), but
  # never with the directory as a trailing file argument - that would be
  # the exact `exec less <directory>` bug this arm exists to prevent.
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" != *"LESS_ARGS:"*"somedir"* ]]
}

# ---- open-in-viewer.sh: command mode never touches the file-viewer
# send-keys path (which types a token in as if it were a repo-relative FILE);
# viewer mode (SG-04) reuses that SAME send-keys path on purpose, see below.

@test "open-in-viewer command mode: hands off to the preview overlay, does not send-keys" {
  cat > "$STUB/jq" <<'JQ'
#!/usr/bin/env bash
exit 1
JQ
  chmod +x "$STUB/jq"
  export QUICKLOOK_TOKEN="TEST_CMD_TOKEN"
  run bash "$VIEWER"
  [ "$status" -eq 0 ]
  # open-preview.sh (the degrade target) builds a `plugin pane open` herdr
  # command; the stub herdr just exits 0, so all we can assert from here is
  # that the file-viewer's own send-keys sequence (which would print
  # nothing distinctive via the herdr stub, but DOES require jq to parse
  # `pane current`/`pane list` first) never got that far - confirmed by jq
  # never having been asked to parse a `pane list` Files-pane query.
  ! grep -q "pane_id" <<<"$output"
}

@test "open-in-viewer viewer mode: reuses the file case's goto-path send-keys sequence" {
  cat > "$STUB/jq" <<'JQ'
#!/usr/bin/env bash
printf '{}'
JQ
  chmod +x "$STUB/jq"
  local hlog
  hlog="$(mktemp)"
  cat > "$STUB/herdr" <<HERDR
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$hlog"
exit 0
HERDR
  chmod +x "$STUB/herdr"
  export QUICKLOOK_TOKEN="TEST_VIEWER_TOKEN"
  run bash "$VIEWER"
  [ "$status" -eq 0 ]
  # SG-04's dir.sh only emits `viewer` once herdr-file-viewer is confirmed
  # installed, so this arm no longer notifies-and-stops (that was the
  # pre-SG-04 placeholder) - it falls into the SAME containment + send-keys
  # flow as a file target. This synthetic target ($FIX/myrepo/somedir) is
  # inside the fixture repo, so it reaches send-keys; the out-of-repo and
  # real-dir.sh cases are covered in tests/handlers-dir.bats.
  grep -qF "pane send-keys {} f" "$hlog"
  grep -qF "pane send-text {} somedir" "$hlog"
  rm -f "$hlog"
}
