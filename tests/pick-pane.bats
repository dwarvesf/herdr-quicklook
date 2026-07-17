#!/usr/bin/env bats
# Tests for the `pick` feature (SG-02, v0.5): scripts/pick.sh (the no-TTY
# action, mirrors scripts/recents.sh) and scripts/pick-pane.sh (the
# fzf-capable overlay pane it opens, mirrors scripts/recents-pane.sh),
# plus a manifest sanity check for the two new herdr-plugin.toml blocks.
#
# Same PATH-stub idiom as recents.bats/pick-scan.bats: script_stubs()
# deliberately drops /opt/homebrew/bin (this host has a real fzf/jq/herdr
# there that must not shadow the stubs - the "absent" tests need
# `command -v` to actually miss, see NOTES.md).
#
# pick_scan_text/pick_count_header (SG-01, v0.5) use `local -A` associative
# arrays and `local -n` namerefs - both bash >=4.3 syntax. macOS SHIPS bash
# 3.2.57 at /bin/bash (last GPLv2 release), and `bash script.sh` resolves
# "bash" via $PATH at invocation time - normally Homebrew's modern bash
# (/opt/homebrew/bin) leads a dev machine's PATH, but this file's own
# script_stubs() deliberately restricts PATH to $STUB:/usr/bin:/bin:/usr/
# local/bin (the NOTES.md gotcha, so a real fzf/jq/herdr can't leak
# through), which resolves bash to the system 3.2 and breaks BOTH
# functions outright (not a crash - `local -A`/`local -n` fail as plain
# builtin errors under `set -u` alone with no `set -e`, so the script
# limps on with broken state and silently wrong output, e.g. header
# "0 on screen" instead of the real count). find_modern_bash() below locates
# a real bash >=4 via the PATH captured before script_stubs narrows it, and
# script_stubs() stubs `$STUB/bash` to exec it directly (shebang points at
# the modern bash's own absolute path, not `/usr/bin/env bash`, so the exec
# doesn't re-enter the restricted PATH and self-loop) - every OTHER tool
# name in $STUB stays a fully controlled stub. See DECISIONS.md: this is a
# latent bash-version requirement in the shipped SG-01 lib, outside this
# sub-goal's `## Touches`, flagged for the conductor/Han rather than
# patched here.

setup() {
  ORIGINAL_PATH="$PATH"
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/state" "$FIX/repo/sub"
  git -C "$FIX/repo" init -q -b main
  printf 'hello\n' >"$FIX/repo/sub/inrepo.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  export XDG_STATE_HOME="$FIX/state"
  unset QUICKLOOK_TOKEN QUICKLOOK_PICK_ORIGIN_PANE QUICKLOOK_PICK_CLIP QUICKLOOK_PICK_SOURCE QUICKLOOK_ROOTS
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# find_modern_bash: the first bash >=4 found on the ORIGINAL PATH (must be
# called before script_stubs narrows $PATH). See the file header comment.
find_modern_bash() {
  local candidate ver saved_ifs
  saved_ifs="$IFS"
  IFS=:
  for candidate in $ORIGINAL_PATH; do
    [ -x "$candidate/bash" ] || continue
    ver="$("$candidate/bash" -c 'printf %s "${BASH_VERSINFO[0]}"' 2>/dev/null)"
    case "$ver" in
      [4-9] | [1-9][0-9]*)
        IFS="$saved_ifs"
        printf '%s/bash' "$candidate"
        return 0
        ;;
    esac
  done
  IFS="$saved_ifs"
  return 1
}

script_stubs() {
  STUB="$(mktemp -d)"
  local modern_bash
  modern_bash="$(find_modern_bash)" || modern_bash="/bin/bash"
  printf '#!%s\nexec %s "$@"\n' "$modern_bash" "$modern_bash" >"$STUB/bash"
  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS: %%s\\n" "$*"\n' >"$STUB/less"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/herdr"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/open"
  # No clipboard by default (exit 1, no output); tests that need a
  # clipboard token override this.
  printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB/pbpaste"
  chmod +x "$STUB/bash" "$STUB/less" "$STUB/herdr" "$STUB/open" "$STUB/pbpaste"
  # Deliberately NOT /opt/homebrew/bin (NOTES.md's PATH-stub gotcha): this
  # host has a real fzf/jq/herdr there that must not shadow the stubs. The
  # $STUB/bash shim above is the one deliberate exception (see file header).
  export PATH="$STUB:/usr/bin:/bin:/usr/local/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
}

jq_stub() {
  cat >"$STUB/jq" <<'SH'
#!/usr/bin/env bash
exec /opt/homebrew/bin/jq "$@"
SH
  chmod +x "$STUB/jq"
}

# ---- scripts/pick.sh (the no-TTY action) ----

@test "pick.sh: opens the pick-pane overlay" {
  script_stubs
  cd "$FIX/repo"
  unset HERDR_PLUGIN_CONTEXT_JSON HERDR_WORKSPACE_CWD
  run bash "$BATS_TEST_DIRNAME/../scripts/pick.sh"
  [ "$status" -eq 0 ]
}

@test "pick.sh: forwards the origin pane id, cwd, and clipboard token on the pane-open argv" {
  script_stubs
  jq_stub
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "current" ]; then
  printf '{"result":{"pane":{"pane_id":"origin-1"}}}\n'
else
  printf '%s\n' "$@"
fi
SH
  chmod +x "$STUB/herdr"
  cat >"$STUB/pbpaste" <<'SH'
#!/usr/bin/env bash
printf 'sub/inrepo.md\n'
SH
  chmod +x "$STUB/pbpaste"
  cd "$FIX/repo"
  export HERDR_PLUGIN_CONTEXT_JSON
  HERDR_PLUGIN_CONTEXT_JSON="$(printf '{"focused_pane_cwd":"%s"}' "$FIX/repo")"
  unset HERDR_WORKSPACE_CWD
  run bash "$BATS_TEST_DIRNAME/../scripts/pick.sh"
  [ "$status" -eq 0 ]
  grep -qx -- 'pick-pane' <<<"$output"
  grep -qx -- 'overlay' <<<"$output"
  grep -qx -- '--cwd' <<<"$output"
  grep -qx -- "$FIX/repo" <<<"$output"
  grep -qx -- 'QUICKLOOK_PICK_ORIGIN_PANE=origin-1' <<<"$output"
  grep -qx -- 'QUICKLOOK_PICK_CLIP=sub/inrepo.md' <<<"$output"
}

@test "pick.sh: empty clipboard emits no QUICKLOOK_PICK_CLIP flag" {
  script_stubs
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@"
SH
  chmod +x "$STUB/herdr"
  cd "$FIX/repo"
  unset HERDR_PLUGIN_CONTEXT_JSON HERDR_WORKSPACE_CWD
  run bash "$BATS_TEST_DIRNAME/../scripts/pick.sh"
  [ "$status" -eq 0 ]
  ! grep -q -- 'QUICKLOOK_PICK_CLIP' <<<"$output"
}

# ---- scripts/pick-pane.sh (the TTY-holding picker) ----

# A herdr stub whose `pane read` reply is the fixed screen text below (one
# real resolvable path, one URL - two kinds, so the count header can be
# asserted on both). No blank lines (see the file header comment).
pane_read_herdr_stub() {
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ]; then
  printf 'open sub/inrepo.md now\n'
  printf 'see https://example.com/a/b for docs\n'
else
  exit 0
fi
SH
  chmod +x "$STUB/herdr"
}

@test "pick-pane.sh: clipboard row is preselected (row 1) and deduped out of the on-screen list; header reflects the on-screen scan" {
  script_stubs
  pane_read_herdr_stub
  cd "$FIX/repo"
  export QUICKLOOK_PICK_ORIGIN_PANE="origin-1"
  export QUICKLOOK_PICK_CLIP="sub/inrepo.md"
  ROWS_LOG="$(mktemp)"
  ARGV_LOG="$(mktemp)"
  cat >"$STUB/fzf" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV_LOG"
cat > "$ROWS_LOG"
sed -n '1p' "$ROWS_LOG"
SH
  chmod +x "$STUB/fzf"
  run bash "$BATS_TEST_DIRNAME/../scripts/pick-pane.sh" </dev/null
  [ "$status" -eq 0 ]
  # row 1 is the clipboard row: hidden raw col = the clip token, display =
  # "clipboard: <token>"
  [ "$(sed -n '1p' "$ROWS_LOG")" = "$(printf 'sub/inrepo.md\tclipboard: sub/inrepo.md')" ]
  # the on-screen scan ALSO found sub/inrepo.md (kind path) - deduped out,
  # so it must not appear a second time as its own row anywhere below row 1
  dupes="$(tail -n +2 "$ROWS_LOG" | grep -c $'^sub/inrepo.md\t' || true)"
  [ "$dupes" -eq 0 ]
  # the generic URL from the same screen is still listed (only the
  # clipboard token itself is deduped, not the whole on-screen list)
  grep -qx $'https://example.com/a/b\thttps://example.com/a/b' "$ROWS_LOG"
  # count header: 2 on screen (the path counted even though its ROW is
  # deduped - the header describes what's ON SCREEN, not the picker rows)
  grep -qx -- '--header=2 on screen · 1 path · 1 url' "$ARGV_LOG"
}

@test "pick-pane.sh: a clipboard token that does NOT resolve is skipped - no clipboard row, on-screen list still shown" {
  script_stubs
  pane_read_herdr_stub
  cd "$FIX/repo"
  export QUICKLOOK_PICK_ORIGIN_PANE="origin-1"
  export QUICKLOOK_PICK_CLIP="totally-nonexistent-file-xyz.md"
  ROWS_LOG="$(mktemp)"
  cat >"$STUB/fzf" <<SH
#!/usr/bin/env bash
cat > "$ROWS_LOG"
sed -n '1p' "$ROWS_LOG"
SH
  chmod +x "$STUB/fzf"
  run bash "$BATS_TEST_DIRNAME/../scripts/pick-pane.sh" </dev/null
  [ "$status" -eq 0 ]
  ! grep -q 'clipboard:' "$ROWS_LOG"
  # the on-screen candidates are still present (path ranks above url)
  [ "$(sed -n '1p' "$ROWS_LOG")" = "$(printf 'sub/inrepo.md\tsub/inrepo.md')" ]
}

@test "pick-pane.sh: Enter opens the picked row through preview-pane.sh, using the RAW token (not a 'clipboard: ' label)" {
  script_stubs
  pane_read_herdr_stub
  cd "$FIX/repo"
  export QUICKLOOK_PICK_ORIGIN_PANE="origin-1"
  export QUICKLOOK_PICK_CLIP="sub/inrepo.md"
  cat >"$STUB/fzf" <<'SH'
#!/usr/bin/env bash
# deterministically choose the URL row (proving Enter can pick something
# other than the preselected row 1, and that the RAW column - not the
# display label - is what crosses to preview-pane.sh)
grep -F $'https://example.com/a/b\t'
SH
  chmod +x "$STUB/fzf"
  run bash "$BATS_TEST_DIRNAME/../scripts/pick-pane.sh" </dev/null
  [ "$status" -eq 0 ]
  # a URL resolves to RESOLVED_MODE=browser in preview-pane.sh: url_open
  # (stubbed) is silent, but record_open still fires before it - the
  # recents log is the observable proof the RAW token (not the clipboard
  # row's display label) reached preview-pane.sh via QUICKLOOK_TOKEN.
  run recents_latest
  [ "$output" = "https://example.com/a/b" ]
}

@test "pick-pane.sh: Enter on the preselected clipboard row opens the raw token, not the display label" {
  script_stubs
  pane_read_herdr_stub
  cd "$FIX/repo"
  export QUICKLOOK_PICK_ORIGIN_PANE="origin-1"
  export QUICKLOOK_PICK_CLIP="sub/inrepo.md"
  cat >"$STUB/fzf" <<'SH'
#!/usr/bin/env bash
sed -n '1p'
SH
  chmod +x "$STUB/fzf"
  run bash "$BATS_TEST_DIRNAME/../scripts/pick-pane.sh" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" == *"$FIX/repo/sub/inrepo.md"* ]]
  run recents_latest
  [ "$output" = "sub/inrepo.md" ]
}

@test "pick-pane.sh: Esc (fzf exits non-zero) opens nothing" {
  script_stubs
  pane_read_herdr_stub
  cd "$FIX/repo"
  export QUICKLOOK_PICK_ORIGIN_PANE="origin-1"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$STUB/fzf"
  chmod +x "$STUB/fzf"
  run bash "$BATS_TEST_DIRNAME/../scripts/pick-pane.sh" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" != *"LESS_ARGS:"* ]]
  run recents_latest
  [ -z "$output" ]
}

@test "pick-pane.sh: zero on-screen candidates and no clipboard -> honest empty state, no crash, fzf never invoked" {
  script_stubs
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ]; then
  printf 'just some ordinary prose\n'
  printf 'nothing here is a path, url, sha, ref, dir, or a real filename\n'
else
  exit 0
fi
SH
  chmod +x "$STUB/herdr"
  FZF_MARKER="$(mktemp)"
  rm -f "$FZF_MARKER"
  cat >"$STUB/fzf" <<SH
#!/usr/bin/env bash
touch "$FZF_MARKER"
exit 1
SH
  chmod +x "$STUB/fzf"
  cd "$FIX/repo"
  export QUICKLOOK_PICK_ORIGIN_PANE="origin-1"
  run bash "$BATS_TEST_DIRNAME/../scripts/pick-pane.sh" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing openable on screen"* ]]
  [ ! -e "$FZF_MARKER" ]
}

@test "pick-pane.sh: no fzf on PATH -> auto-opens row 1 (clipboard-preselected), no interactive step" {
  script_stubs
  pane_read_herdr_stub
  cd "$FIX/repo"
  export QUICKLOOK_PICK_ORIGIN_PANE="origin-1"
  export QUICKLOOK_PICK_CLIP="sub/inrepo.md"
  # script_stubs' PATH has no fzf.
  run bash "$BATS_TEST_DIRNAME/../scripts/pick-pane.sh" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"* ]]
  [[ "$output" == *"$FIX/repo/sub/inrepo.md"* ]]
}

# ---- manifest sanity ----

@test "herdr-plugin.toml: parses and contains the pick action + pick-pane overlay" {
  python3 - "$BATS_TEST_DIRNAME/../herdr-plugin.toml" <<'PY'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
action_ids = [a["id"] for a in data["actions"]]
pane_ids = [p["id"] for p in data["panes"]]
assert "pick" in action_ids, action_ids
assert "pick-pane" in pane_ids, pane_ids
pick_action = next(a for a in data["actions"] if a["id"] == "pick")
assert pick_action["command"] == ["bash", "scripts/pick.sh"], pick_action
pick_pane = next(p for p in data["panes"] if p["id"] == "pick-pane")
assert pick_pane["command"] == ["bash", "scripts/pick-pane.sh"], pick_pane
PY
}
