#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  LIB="$ROOT/scripts/lib.sh"
  HINT_PANE="$ROOT/scripts/hint-pane.sh"
  OPEN_LINK="$ROOT/scripts/open-link.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo/src" "$FIX/state"
  git -C "$FIX/repo" init -q -b main
  printf 'package main\n' >"$FIX/repo/src/x.go"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  STUB="$(mktemp -d)"
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@"
SH
  chmod +x "$STUB/herdr"
  export PATH="$STUB:/opt/homebrew/bin:/usr/bin:/bin:/usr/local/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
  export XDG_STATE_HOME="$FIX/state"
  unset HERDR_PLUGIN_CLICKED_URL HERDR_PLUGIN_LINK_HANDLER_ID HERDR_PLUGIN_CONTEXT_JSON HERDR_PANE_ID
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

@test "virtual link URI round-trips a path with spaces and a line" {
  token="src/naïve + file.go:42"
  uri="$(quicklook_link_uri "$token")"
  [[ "$uri" == https://herdr-quicklook.invalid/open\?token=* ]]
  run quicklook_token_from_link "$uri"
  [ "$status" -eq 0 ]
  [ "$output" = "$token" ]
}

@test "virtual link decoder rejects foreign and non-canonical URLs" {
  run quicklook_token_from_link "https://example.com/open?token=src%2Fx.go"
  [ "$status" -ne 0 ]
  run quicklook_token_from_link "${QUICKLOOK_LINK_PREFIX}src%2fx.go"
  [ "$status" -ne 0 ]
  run quicklook_token_from_link "${QUICKLOOK_LINK_PREFIX}src%2Fx.go&extra=1"
  [ "$status" -ne 0 ]
}

@test "hint pane overlays hint letters in place on the snapshot" {
  cd "$FIX/repo"
  snap_file="$FIX/snap"
  printf 'changed src/x.go:7 today\n' >"$snap_file"
  printf 'see https://example.com/docs\n' >>"$snap_file"
  tokens_file="$FIX/tokens"
  printf 'src/x.go:7\t1\tpath  src/x.go:7\n' >"$tokens_file"
  printf 'https://example.com/docs\t2\turl   https://example.com/docs\n' >>"$tokens_file"
  export QUICKLOOK_HINT_TOKENS_FILE="$tokens_file"
  export QUICKLOOK_HINT_SNAP_FILE="$snap_file"
  run bash "$HINT_PANE" </dev/null
  [ "$status" -eq 0 ]
  path_uri="$(quicklook_link_uri 'src/x.go:7')"
  url_uri="$(quicklook_link_uri 'https://example.com/docs')"
  [[ "$output" == *"$path_uri"* ]]
  [[ "$output" == *"$url_uri"* ]]
  # In-place overlay: the hint letter replaces the token's first char inside
  # the snapshot line, inverse-video; the surrounding text is untouched.
  [[ "$output" == *"changed "* ]]
  [[ "$output" == *$'\033[1;7ma\033[0m\033[4mrc/x.go:7\033[0m'* ]]
  [[ "$output" == *$'\033[1;7ms\033[0m\033[4mttps://example.com/docs\033[0m'* ]]
  [[ "$output" == *"Ctrl+click"* ]]
}

@test "hint pane parks an unmatchable token in the extras list" {
  cd "$FIX/repo"
  snap_file="$FIX/snap"
  printf 'nothing relevant here\n' >"$snap_file"
  tokens_file="$FIX/tokens"
  printf 'src/x.go:7\t1\tpath  src/x.go:7\n' >"$tokens_file"
  export QUICKLOOK_HINT_TOKENS_FILE="$tokens_file"
  export QUICKLOOK_HINT_SNAP_FILE="$snap_file"
  run bash "$HINT_PANE" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing relevant here"* ]]
  [[ "$output" == *"path  src/x.go:7"* ]]
}

@test "virtual link action decodes the token before opening preview" {
  export HERDR_PLUGIN_CLICKED_URL
  HERDR_PLUGIN_CLICKED_URL="$(quicklook_link_uri 'src/x.go:7')"
  export HERDR_PLUGIN_CONTEXT_JSON
  HERDR_PLUGIN_CONTEXT_JSON="$(jq -cn --arg cwd "$FIX/repo" '{focused_pane_cwd:$cwd}')"
  run bash "$OPEN_LINK"
  [ "$status" -eq 0 ]
  grep -qx 'QUICKLOOK_TOKEN=src/x.go:7' <<<"$output"
  ! grep -q 'herdr-quicklook.invalid' <<<"$output"
}

@test "manifest registers the hint overlay, ordered handlers, and agent hook" {
  python3 - "$ROOT/herdr-plugin.toml" <<'PY'
import re
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
actions = {item["id"]: item for item in data["actions"]}
panes = {item["id"]: item for item in data["panes"]}
assert actions["hint"]["command"] == ["bash", "scripts/hint.sh"]
assert actions["open-link"]["command"] == ["bash", "scripts/open-link.sh"]
assert actions["agent-suggestion"]["command"] == ["bash", "scripts/open-suggestion.sh"]
assert panes["hint-pane"]["placement"] == "overlay"
# The superseded pickers must stay gone.
for dead in ("pick", "linkify", "pluck-chain"):
    assert dead not in actions, dead
for dead_pane in ("pick-pane", "linkify-pane"):
    assert dead_pane not in panes, dead_pane
handlers = data["link_handlers"]
assert [item["id"] for item in handlers] == ["virtual-token", "git-host-token"]
assert handlers[0]["action"] == "open-link"
assert handlers[1]["action"] == "preview"
for handler in handlers:
    re.compile(handler["pattern"])
git_pattern = re.compile(handlers[1]["pattern"])
assert git_pattern.fullmatch("https://github.com/o/r/blob/main/src/x.go#L42")
assert git_pattern.fullmatch("https://github.com/o/r/pull/42")
assert git_pattern.fullmatch("https://gitlab.com/o/r/-/blob/main/src/x.go")
assert git_pattern.fullmatch("https://bitbucket.org/o/r/src/main/src/x.go")
assert not git_pattern.fullmatch("https://example.com/docs")
assert not git_pattern.fullmatch("https://github.com/o/r/issues/42")
assert data["events"] == [{
    "on": "pane.agent_status_changed",
    "platforms": ["linux", "macos"],
    "command": ["bash", "scripts/agent-suggest.sh"],
}]
PY
}
