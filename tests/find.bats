#!/usr/bin/env bats
# The `find` fuzzy file finder: action/pane wiring + degrade paths.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  FIND="$ROOT/scripts/find.sh"
  FIND_PANE="$ROOT/scripts/find-pane.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo/src"
  git -C "$FIX/repo" init -q -b main
  printf 'hello find\n' >"$FIX/repo/src/target.md"
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
  unset QUICKLOOK_TOKEN QUICKLOOK_FIND_CWD HERDR_PLUGIN_CONTEXT_JSON
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

@test "find action forwards the origin cwd as env, never --cwd" {
  export HERDR_PLUGIN_CONTEXT_JSON
  HERDR_PLUGIN_CONTEXT_JSON="$(jq -cn --arg cwd "$FIX/repo" '{focused_pane_cwd:$cwd}')"
  run bash "$FIND"
  [ "$status" -eq 0 ]
  grep -qx 'find-pane' <<<"$output"
  grep -qx "QUICKLOOK_FIND_CWD=$FIX/repo" <<<"$output"
  ! grep -qx -- '--cwd' <<<"$output"
}

@test "find pane without fzf degrades to a message, no crash" {
  export PATH="$STUB:/usr/bin:/bin"
  export QUICKLOOK_FIND_CWD="$FIX/repo"
  run bash "$FIND_PANE" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs fzf"* ]]
}

@test "find pane renders the fzf pick through the preview path" {
  cat >"$STUB/fzf" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf 'src/target.md\n'
SH
  cat >"$STUB/less" <<'SH'
#!/usr/bin/env bash
printf 'LESS_ARGS: %s\n' "$*"
SH
  chmod +x "$STUB/fzf" "$STUB/less"
  export PATH="$STUB:/usr/bin:/bin"
  export QUICKLOOK_FIND_CWD="$FIX/repo"
  run bash "$FIND_PANE" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"LESS_ARGS:"*"src/target.md"* ]]
}

@test "manifest registers the find overlay and action" {
  python3 - "$ROOT/herdr-plugin.toml" <<'PY'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
actions = {item["id"]: item for item in data["actions"]}
panes = {item["id"]: item for item in data["panes"]}
assert actions["find"]["command"] == ["bash", "scripts/find.sh"]
assert panes["find-pane"]["placement"] == "overlay"
PY
}
