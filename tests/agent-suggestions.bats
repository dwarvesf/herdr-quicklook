#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  SCRIPT="$ROOT/scripts/agent-suggest.sh"
  OPEN="$ROOT/scripts/open-suggestion.sh"
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo/src" "$FIX/state" "$FIX/config"
  git -C "$FIX/repo" init -q -b main
  printf 'package main\n' >"$FIX/repo/src/new.go"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  PANE_TEXT="$FIX/pane.txt"
  HERDR_LOG="$FIX/herdr.log"
  : >"$PANE_TEXT"
  : >"$HERDR_LOG"
  STUB="$(mktemp -d)"
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ]; then
  printf 'pane-read\n' >>"$HERDR_LOG"
  cat "$PANE_TEXT"
elif [ "$1" = "notification" ]; then
  printf 'notification:%s\n' "$*" >>"$HERDR_LOG"
else
  printf 'command:%s\n' "$*" >>"$HERDR_LOG"
  printf '%s\n' "$@"
fi
SH
  chmod +x "$STUB/herdr"

  export PATH="$STUB:/opt/homebrew/bin:/usr/bin:/bin:/usr/local/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
  export HERDR_PLUGIN_STATE_DIR="$FIX/state"
  export HERDR_PLUGIN_CONFIG_DIR="$FIX/config"
  export HERDR_LOG PANE_TEXT
  export HERDR_PLUGIN_CONTEXT_JSON
  HERDR_PLUGIN_CONTEXT_JSON="$(jq -cn --arg cwd "$FIX/repo" '{focused_pane_id:"w1-1",focused_pane_cwd:$cwd}')"
  printf 'QUICKLOOK_AGENT_SUGGESTIONS=notify\n' >"$FIX/config/.env"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

set_event() {
  export HERDR_PLUGIN_EVENT_JSON
  HERDR_PLUGIN_EVENT_JSON="$(jq -cn --arg status "$1" '{event:"pane_agent_status_changed",data:{type:"pane_agent_status_changed",pane_id:"w1-1",workspace_id:"w1",agent_status:$status}}')"
}

@test "disabled agent suggestions exit without reading the pane" {
  printf 'QUICKLOOK_AGENT_SUGGESTIONS=off\n' >"$FIX/config/.env"
  set_event working
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$HERDR_LOG" ]
  [ ! -e "$FIX/state/agent-suggestions/w1-1.baseline" ]
}

@test "a stale per-pane lock is recovered on the next event" {
  mkdir -p "$FIX/state/agent-suggestions/w1-1.lock"
  printf '99999999\n' >"$FIX/state/agent-suggestions/w1-1.lock/pid"
  printf 'start\n' >"$PANE_TEXT"
  set_event working
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$FIX/state/agent-suggestions/w1-1.baseline" ]
  [ ! -e "$FIX/state/agent-suggestions/w1-1.lock" ]
}

@test "agent completion scans only output added after the working baseline" {
  printf 'old https://example.com/stale\n' >"$PANE_TEXT"
  set_event working
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$FIX/state/agent-suggestions/w1-1.baseline" ]

  printf 'old https://example.com/stale\nchanged src/new.go:7\n' >"$PANE_TEXT"
  set_event done
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  latest="$FIX/state/agent-suggestions/latest.json"
  [ "$(jq -r .token "$latest")" = "src/new.go:7" ]
  [ "$(jq -r .cwd "$latest")" = "$FIX/repo" ]
  grep -q 'notification:notification show quicklook suggestion --body src/new.go:7' "$HERDR_LOG"
  [ ! -e "$FIX/state/agent-suggestions/w1-1.baseline" ]
}

@test "repeated working and idle presentation events do not reset or duplicate a turn" {
  printf 'start\n' >"$PANE_TEXT"
  set_event working
  bash "$SCRIPT"
  printf 'start\nmentioned src/new.go:9\n' >"$PANE_TEXT"
  set_event working
  bash "$SCRIPT"
  printf 'start\nmentioned src/new.go:9\nfinished\n' >"$PANE_TEXT"
  set_event idle
  bash "$SCRIPT"
  set_event idle
  bash "$SCRIPT"
  [ "$(jq -r .token "$FIX/state/agent-suggestions/latest.json")" = "src/new.go:9" ]
  [ "$(grep -c '^notification:' "$HERDR_LOG")" -eq 1 ]
}

@test "preview mode opens the detected token at the agent pane cwd" {
  printf 'QUICKLOOK_AGENT_SUGGESTIONS=preview\n' >"$FIX/config/.env"
  printf 'start\n' >"$PANE_TEXT"
  set_event working
  bash "$SCRIPT"
  printf 'start\nchanged src/new.go:11\n' >"$PANE_TEXT"
  set_event done
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'command:plugin pane open' "$HERDR_LOG"
  grep -qx 'QUICKLOOK_TOKEN=src/new.go:11' <<<"$output"
  grep -qx "$FIX/repo" <<<"$output"
}

@test "latest suggestion action opens saved token with its original cwd" {
  mkdir -p "$FIX/state/agent-suggestions"
  jq -n --arg token 'src/new.go:13' --arg cwd "$FIX/repo" '{token:$token,cwd:$cwd}' >"$FIX/state/agent-suggestions/latest.json"
  run bash "$OPEN"
  [ "$status" -eq 0 ]
  grep -qx 'QUICKLOOK_TOKEN=src/new.go:13' <<<"$output"
  grep -qx "$FIX/repo" <<<"$output"
}
