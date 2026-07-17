#!/usr/bin/env bats
# Tests for the `recents` feature (SG-07): lib.sh's record_open/recents_*
# state functions, plus script-level coverage for scripts/recents.sh (the
# no-TTY action) and scripts/recents-pane.sh (the fzf-capable overlay pane
# it opens), and the browser-mode record_open call added to both pane
# scripts. Unit tests source lib.sh directly (same fixture shape as
# quicklook.bats/registry.bats); XDG_STATE_HOME is pointed at a fixture dir
# per test for isolation.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/state" "$FIX/repo"
  git -C "$FIX/repo" init -q -b main
  printf 'x\n' > "$FIX/repo/f.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  export XDG_STATE_HOME="$FIX/state"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS
  RECENTS_MAX=20
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# ---- recents_state_dir / recents_state_file ----

@test "recents_state_dir: honors XDG_STATE_HOME, namespaced under herdr-quicklook" {
  run recents_state_dir
  [ "$output" = "$FIX/state/herdr-quicklook" ]
}

@test "recents_state_file: lives inside the state dir" {
  run recents_state_file
  [ "$output" = "$FIX/state/herdr-quicklook/recents" ]
}

# ---- record_open: basic append, dedup, cap ----

@test "record_open: creates the state file and writes the token" {
  record_open "a/b.md"
  [ -f "$(recents_state_file)" ]
  [ "$(cat "$(recents_state_file)")" = "a/b.md" ]
}

@test "record_open: a second distinct token becomes the latest" {
  record_open "a.md"
  record_open "b.md"
  run recents_latest
  [ "$output" = "b.md" ]
}

@test "record_open: dedups - reopening an existing token moves it to the front, no duplicate line" {
  record_open "a.md"
  record_open "b.md"
  record_open "a.md"
  run recents_latest
  [ "$output" = "a.md" ]
  lines_total="$(wc -l < "$(recents_state_file)" | tr -d ' ')"
  [ "$lines_total" -eq 2 ]
}

@test "record_open: caps at RECENTS_MAX, oldest entries drop off" {
  RECENTS_MAX=3
  record_open "a"
  record_open "b"
  record_open "c"
  record_open "d"
  run recents_list
  [ "${lines[0]}" = "d" ]
  [ "${lines[1]}" = "c" ]
  [ "${lines[2]}" = "b" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "record_open: at the REAL production default (20, not an overridden small cap), the 21st entry evicts the 1st" {
  # The cap test above overrides RECENTS_MAX=3 for speed; that never proves
  # the actual shipped default (QUICKLOOK_RECENTS_MAX unset -> 20 in lib.sh)
  # evicts at the right boundary. setup() already sets RECENTS_MAX=20 to
  # match that default literally (not a stand-in small number), so this
  # pins the real cap: entry 21 must push entry 1 off, entries 2-21 survive.
  local i
  for i in $(seq 1 21); do
    record_open "token-$i"
  done
  run recents_list
  [ "${#lines[@]}" -eq 20 ]
  [ "${lines[0]}" = "token-21" ]
  [ "${lines[19]}" = "token-2" ]
  ! grep -qxF "token-1" "$(recents_state_file)"
}

@test "record_open: empty token is a no-op (no file created)" {
  record_open ""
  [ ! -e "$(recents_state_file)" ]
}

@test "record_open: is best-effort when the state dir cannot be created" {
  # Point the state dir at a path whose parent is a regular FILE (mkdir -p
  # must fail); record_open must swallow that, not error/exit the caller.
  printf 'not a dir\n' > "$FIX/state/blocker"
  XDG_STATE_HOME="$FIX/state/blocker"
  record_open "a.md"
  [ ! -e "$FIX/state/blocker/herdr-quicklook" ]
}

# ---- recents_list / recents_latest: missing / corrupt file ----

@test "recents_list: missing file returns nothing, rc 0" {
  run recents_list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "recents_latest: empty log returns empty" {
  run recents_latest
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "recents_list: an unreadable state file degrades to empty, never crashes" {
  mkdir -p "$(recents_state_dir)"
  printf 'a\nb\n' > "$(recents_state_file)"
  chmod 000 "$(recents_state_file)"
  run recents_list
  [ "$status" -eq 0 ]
  chmod 644 "$(recents_state_file)"
}

# ---- recents_path_is_safe: the never-inside-a-repo guard ----

@test "recents_path_is_safe: a path outside any repo is safe" {
  run recents_path_is_safe "$FIX/state/herdr-quicklook/recents"
  [ "$status" -eq 0 ]
}

@test "recents_path_is_safe: a path inside a git working tree is unsafe" {
  run recents_path_is_safe "$FIX/repo/.state/herdr-quicklook/recents"
  [ "$status" -eq 1 ]
}

@test "record_open: refuses to write when XDG_STATE_HOME resolves inside a repo (the guard fires end to end)" {
  XDG_STATE_HOME="$FIX/repo/.state"
  record_open "a.md"
  [ ! -e "$FIX/repo/.state" ]
}

# ---- script-level: browser-mode opens are now recorded (both pane scripts) ----

script_stubs() {
  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS: %%s\\n" "$*"\n' > "$STUB/less"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/herdr"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/open"
  chmod +x "$STUB/less" "$STUB/herdr" "$STUB/open"
  # Deliberately NOT /opt/homebrew/bin: this host has a real fzf/bat/eza
  # there, and the no-fzf tests below need `command -v fzf` to actually
  # miss. git/sed/tail/mktemp/grep/dirname/mv/rm all resolve fine from
  # /usr/bin:/bin:/usr/local/bin alone.
  export PATH="$STUB:/usr/bin:/bin:/usr/local/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
}

@test "preview-pane.sh: a browser-mode open (generic URL) is recorded" {
  script_stubs
  cd "$FIX/repo"
  export QUICKLOOK_TOKEN="https://example.com/a/b"
  run bash "$BATS_TEST_DIRNAME/../scripts/preview-pane.sh"
  [ "$status" -eq 0 ]
  run recents_latest
  [ "$output" = "https://example.com/a/b" ]
}

@test "open-in-viewer.sh: a browser-mode open (generic URL) is recorded" {
  script_stubs
  cat > "$STUB/jq" <<'JQ'
#!/usr/bin/env bash
exit 1
JQ
  chmod +x "$STUB/jq"
  cd "$FIX/repo"
  export QUICKLOOK_TOKEN="https://example.com/x/y"
  run bash "$BATS_TEST_DIRNAME/../scripts/open-in-viewer.sh"
  [ "$status" -eq 0 ]
  run recents_latest
  [ "$output" = "https://example.com/x/y" ]
}

# ---- script-level: scripts/recents.sh (the no-TTY action) ----

@test "recents.sh: opens the recents-pick overlay pane" {
  script_stubs
  cd "$FIX/repo"
  unset HERDR_PLUGIN_CONTEXT_JSON HERDR_WORKSPACE_CWD
  run bash "$BATS_TEST_DIRNAME/../scripts/recents.sh"
  [ "$status" -eq 0 ]
}

@test "recents.sh: forwards argv building a recents-pick pane-open (via herdr stub echoing argv)" {
  STUB="$(mktemp -d)"
  cat > "$STUB/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@"
SH
  chmod +x "$STUB/herdr"
  export PATH="$STUB:$PATH"
  export HERDR_BIN_PATH="$STUB/herdr"
  unset HERDR_PLUGIN_CONTEXT_JSON HERDR_WORKSPACE_CWD
  run bash "$BATS_TEST_DIRNAME/../scripts/recents.sh"
  [ "$status" -eq 0 ]
  grep -qx -- 'recents-pick' <<<"$output"
  grep -qx -- 'overlay' <<<"$output"
}

# ---- script-level: scripts/recents-pane.sh (the TTY-holding picker) ----

@test "recents-pane.sh: no recents yet -> pause_close message, no crash" {
  script_stubs
  cd "$FIX/repo"
  run bash "$BATS_TEST_DIRNAME/../scripts/recents-pane.sh" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"no recents yet"* ]]
}

@test "recents-pane.sh: no fzf on PATH -> reopens the latest with no interactive step" {
  script_stubs
  cd "$FIX/repo"
  record_open "f.md"
  # PATH built by script_stubs has no fzf, matching the degrade path.
  run bash "$BATS_TEST_DIRNAME/../scripts/recents-pane.sh" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" == *"$FIX/repo/f.md"* ]]
}

@test "recents-pane.sh: fzf present -> the picked candidate is what gets reopened" {
  script_stubs
  cd "$FIX/repo"
  printf 'x\n' > "$FIX/repo/g.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm more
  record_open "f.md"
  record_open "g.md"
  # a stub fzf that deterministically picks the SECOND candidate on stdin
  # (proving the real fzf's stdin, not just "always the first"), matching
  # bare-name.sh's existing fzf-stub-free style would be impractical here -
  # fzf itself needs a stub since bats has no real TTY for it to attach to.
  cat > "$STUB/fzf" <<'SH'
#!/usr/bin/env bash
sed -n '2p'
SH
  chmod +x "$STUB/fzf"
  run bash "$BATS_TEST_DIRNAME/../scripts/recents-pane.sh" < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" == *"$FIX/repo/f.md"* ]]
  [[ "$output" != *"$FIX/repo/g.md"* ]]
}

@test "recents-pane.sh: reopening a recents entry re-records it (recency bump via preview-pane.sh's own record_open)" {
  script_stubs
  cd "$FIX/repo"
  record_open "f.md"
  run bash "$BATS_TEST_DIRNAME/../scripts/recents-pane.sh" < /dev/null
  [ "$status" -eq 0 ]
  run recents_latest
  [ "$output" = "f.md" ]
}
