#!/usr/bin/env bats
# Tests for scripts/handlers/dir.sh (SG-04 dir-targets). Unit-style cases
# source lib.sh directly and read the RESOLVED_* globals match_dir/handle_dir
# communicate through, same fixture/pattern as tests/registry.bats (not
# `run`, which would hide those globals in a subshell). Script-level cases
# drive preview-pane.sh / open-in-viewer.sh as real fresh processes, same
# style as tests/dispatch-modes.bats, to prove the render-mode a real dir.sh
# picks actually reaches the right pane-script arm.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  PREVIEW="$BATS_TEST_DIRNAME/../scripts/preview-pane.sh"
  VIEWER="$BATS_TEST_DIRNAME/../scripts/open-in-viewer.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo/adir/sub" "$FIX/roots/other" "$FIX/outside/adir"
  git -C "$FIX/repo" init -q -b main
  printf 'hello\n' > "$FIX/repo/adir/note.md"
  printf 'a file\n' > "$FIX/repo/afile.md"
  printf 'shadow file\n' > "$FIX/repo/shadowname"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  STUB="$(mktemp -d)"
  HLOG="$(mktemp)"
  # herdr stub: logs every invocation (grep-able below); the herdr-file-viewer
  # install check (`plugin action list --plugin herdr-file-viewer`) succeeds
  # only when HERDR_VIEWER_INSTALLED=1, so each test controls it explicitly.
  cat > "$STUB/herdr" <<HERDR
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$HLOG"
if [ "\$1" = "plugin" ] && [ "\$2" = "action" ] && [ "\$3" = "list" ]; then
  [ "\${HERDR_VIEWER_INSTALLED:-0}" = "1" ] && exit 0
  exit 1
fi
exit 0
HERDR
  chmod +x "$STUB/herdr"
  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS: %%s\\n" "$*"\n' > "$STUB/less"
  chmod +x "$STUB/less"
  cat > "$STUB/jq" <<'JQ'
#!/usr/bin/env bash
printf '{}'
JQ
  chmod +x "$STUB/jq"

  cd "$FIX/repo"
  # deliberately excludes /opt/homebrew/bin (eza's real location on the dev
  # box) so "eza absent" is the true default; individual tests add a fake
  # eza into $STUB when they need the "eza present" branch.
  export PATH="$STUB:/usr/bin:/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS HERDR_VIEWER_INSTALLED
  bat() { return 127; }
  export -f bat 2>/dev/null || true

  # shellcheck disable=SC1090
  . "$LIB"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
  rm -f "$HLOG"
}

# ---- a dir token resolves to the dir + render-mode ----

@test "match_dir accepts a directory" {
  rc=0
  match_dir "adir" || rc=$?
  [ "$rc" -eq 0 ]
}

@test "handle_dir resolves the absolute dir path with no RESOLVED_LINE" {
  handle_dir "adir"
  [ "$RESOLVED_TARGET" = "$FIX/repo/adir" ]
  [ -z "$RESOLVED_LINE" ]
}

@test "handle_dir: herdr-file-viewer installed -> RESOLVED_MODE=viewer" {
  export HERDR_VIEWER_INSTALLED=1
  handle_dir "adir"
  [ "$RESOLVED_MODE" = "viewer" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/adir" ]
}

@test "handle_dir resolves via QUICKLOOK_ROOTS when not present locally" {
  mkdir -p "$FIX/roots/other/onlyinroots"
  export QUICKLOOK_ROOTS="$FIX/roots/other"
  rc=0
  match_dir "onlyinroots" || rc=$?
  [ "$rc" -eq 0 ]
  handle_dir "onlyinroots"
  [ "$RESOLVED_TARGET" = "$FIX/roots/other/onlyinroots" ]
}

# ---- a file token still resolves as file, dir never shadows it ----

@test "match_dir declines a regular file" {
  rc=0
  match_dir "afile.md" || rc=$?
  [ "$rc" -eq 1 ]
}

@test "resolve_any_token: a plain file token still resolves as mode=file" {
  resolve_any_token "afile.md"; rc=$?
  [ "$rc" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/afile.md" ]
}

# ---- negative control: an earlier-priority file always beats a
# later-priority directory of the same name (the quality bar's "resolution
# tests file first, dir second" requirement) ----

@test "negative control: a QUICKLOOK_ROOTS directory never shadows a higher-priority local file of the same name" {
  mkdir -p "$FIX/roots/other/shadowname"
  export QUICKLOOK_ROOTS="$FIX/roots/other"
  rc=0
  match_dir "shadowname" || rc=$?
  [ "$rc" -eq 1 ]
  resolve_any_token "shadowname"; rc2=$?
  [ "$rc2" -eq 0 ]
  [ "$RESOLVED_MODE" = "file" ]
  [ "$RESOLVED_TARGET" = "$FIX/repo/shadowname" ]
}

# ---- negative control: an unresolvable token is declined cleanly, not
# accidentally accepted as a directory ----

@test "negative control: a token matching neither file nor dir falls through with no globals set" {
  rc=0
  resolve_any_token "no/such/thing" || rc=$?
  [ "$rc" -eq 1 ]
  [ -z "$RESOLVED_TARGET" ]
  [ -z "$RESOLVED_MODE" ]
}

# ---- eza-absent falls back to ls ----

@test "handle_dir: herdr-file-viewer absent + eza absent -> command mode runs ls -la" {
  handle_dir "adir"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${RESOLVED_CMD[0]}" = "ls" ]
  [ "${RESOLVED_CMD[1]}" = "-la" ]
  [ "${RESOLVED_CMD[2]}" = "$FIX/repo/adir" ]
}

@test "handle_dir: herdr-file-viewer absent + eza present -> command mode runs eza --tree" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/eza"
  chmod +x "$STUB/eza"
  handle_dir "adir"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${RESOLVED_CMD[0]}" = "eza" ]
  [ "${RESOLVED_CMD[1]}" = "--tree" ]
  [ "${RESOLVED_CMD[2]}" = "$FIX/repo/adir" ]
}

# ---- viewer-absent falls back to the popup tree (script-level, real dir.sh) ----

@test "preview-pane: a directory token pages a tree listing when herdr-file-viewer is absent" {
  export QUICKLOOK_TOKEN="adir"
  run bash "$PREVIEW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"* ]]
  # the directory never appears as a trailing `less` file argument - that
  # would be the exec-less-on-a-directory bug the viewer/command arms exist
  # to prevent; it's piped into less's stdin instead.
  [[ "$output" != *"LESS_ARGS:"*"adir"* ]]
}

# ---- viewer-root helper: open-in-viewer.sh drives the real file-viewer
# pane at the directory when the plugin is installed ----

@test "open-in-viewer: a directory inside the repo sends the goto-path keys" {
  export HERDR_VIEWER_INSTALLED=1
  export QUICKLOOK_TOKEN="adir"
  run bash "$VIEWER"
  [ "$status" -eq 0 ]
  grep -qF "pane send-keys {} f" "$HLOG"
  grep -qF "pane send-text {} adir" "$HLOG"
  grep -qF "pane send-keys {} Enter" "$HLOG"
}

@test "negative control: a directory outside the repo notifies and never sends keys" {
  export HERDR_VIEWER_INSTALLED=1
  export QUICKLOOK_TOKEN="$FIX/outside/adir"
  run bash "$VIEWER"
  [ "$status" -eq 0 ]
  grep -q "notification show quicklook --body outside this repo" "$HLOG"
  ! grep -q "pane send-keys" "$HLOG"
}
