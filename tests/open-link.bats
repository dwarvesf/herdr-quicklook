#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  LIB="$ROOT/scripts/lib.sh"
  LINKIFY="$ROOT/scripts/linkify.sh"
  LINKIFY_PANE="$ROOT/scripts/linkify-pane.sh"
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

@test "linkify action forwards the origin pane and cwd into an overlay" {
  export HERDR_PLUGIN_CONTEXT_JSON
  HERDR_PLUGIN_CONTEXT_JSON="$(jq -cn --arg cwd "$FIX/repo" '{focused_pane_id:"w1-1",focused_pane_cwd:$cwd}')"
  run bash "$LINKIFY"
  [ "$status" -eq 0 ]
  grep -qx 'linkify-pane' <<<"$output"
  grep -qx 'overlay' <<<"$output"
  grep -qx 'QUICKLOOK_LINKIFY_ORIGIN_PANE=w1-1' <<<"$output"
  grep -qx "$FIX/repo" <<<"$output"
}

@test "linkify pane renders scanner candidates as OSC-8 sentinel links" {
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ]; then
  printf 'changed src/x.go:7\n'
  printf 'see https://example.com/docs\n'
fi
SH
  chmod +x "$STUB/herdr"
  cd "$FIX/repo"
  export QUICKLOOK_LINKIFY_ORIGIN_PANE="w1-1"
  run bash "$LINKIFY_PANE" </dev/null
  [ "$status" -eq 0 ]
  path_uri="$(quicklook_link_uri 'src/x.go:7')"
  url_uri="$(quicklook_link_uri 'https://example.com/docs')"
  [[ "$output" == *"$path_uri"* ]]
  [[ "$output" == *"$url_uri"* ]]
  [[ "$output" == *"Ctrl+click to open"* ]]
}

@test "linkify pane refreshes the origin snapshot and q closes" {
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ]; then
  printf 'changed src/x.go:7\n'
fi
SH
  chmod +x "$STUB/herdr"
  cd "$FIX/repo"
  export QUICKLOOK_LINKIFY_ORIGIN_PANE="w1-1"
  run bash "$LINKIFY_PANE" <<<"rq"
  [ "$status" -eq 0 ]
  [ "$(grep -c '1 on screen' <<<"$output")" -eq 2 ]
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

@test "manifest registers linkify actions, overlay, ordered handlers, and agent hook" {
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
assert actions["linkify"]["command"] == ["bash", "scripts/linkify.sh"]
assert actions["open-link"]["command"] == ["bash", "scripts/open-link.sh"]
assert actions["agent-suggestion"]["command"] == ["bash", "scripts/open-suggestion.sh"]
assert panes["linkify-pane"]["placement"] == "overlay"
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
