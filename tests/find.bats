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

@test "find pane pre-seeds the fzf query from QUICKLOOK_FIND_QUERY" {
  cat >"$STUB/fzf" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
q=""
while [ $# -gt 0 ]; do
  [ "$1" = "--query" ] && q="$2"
  shift
done
printf 'QUERY_SEEN:%s\n' "$q" >&2
exit 130
SH
  chmod +x "$STUB/fzf"
  export PATH="$STUB:/usr/bin:/bin"
  export QUICKLOOK_FIND_CWD="$FIX/repo"
  export QUICKLOOK_FIND_QUERY="src/targ"
  run bash "$FIND_PANE" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"QUERY_SEEN:src/targ"* ]]
}

@test "hint action routes a visible-but-unresolvable clipboard path into the seeded finder" {
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ]; then
  printf 'agent said src/targ.md is broken\n'
  exit 0
fi
printf '%s\n' "$@"
SH
  cat >"$STUB/pbpaste" <<'SH'
#!/usr/bin/env bash
printf 'src/targ.md'
SH
  chmod +x "$STUB/herdr" "$STUB/pbpaste"
  export PATH="$STUB:/opt/homebrew/bin:/usr/bin:/bin"
  export HERDR_PLUGIN_CONTEXT_JSON
  HERDR_PLUGIN_CONTEXT_JSON="$(jq -cn --arg cwd "$FIX/repo" '{focused_pane_id:"w1-1",focused_pane_cwd:$cwd}')"
  run bash "$ROOT/scripts/hint.sh"
  [ "$status" -eq 0 ]
  grep -qx 'find-pane' <<<"$output"
  grep -qx 'QUICKLOOK_FIND_QUERY=src/targ.md' <<<"$output"
}

# The default is `overlay`, not `popup`. A popup is ANONYMOUS: herdr returns
# no pane_id for it and it never appears in `pane list`, so `hint` cannot
# target it for a second overlay and pane_is_preview cannot match it for a
# stack push. A pick landing there ends the drill-down.
@test "open-popup forwards the token into an addressable overlay by default" {
  cat >"$STUB/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FIX/sent.log"
SH
  chmod +x "$STUB/herdr"
  export HERDR_BIN_PATH="$STUB/herdr"
  run bash "$ROOT/scripts/open-popup.sh" 'src/target.md'
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6; do [ -f "$FIX/sent.log" ] && break; sleep 0.3; done
  grep -q -- '--placement overlay' "$FIX/sent.log"
  ! grep -q -- '--width' "$FIX/sent.log"
  grep -q -- 'QUICKLOOK_TOKEN=src/target.md' "$FIX/sent.log"
}

@test "open-popup honors QUICKLOOK_OPEN_PLACEMENT=popup (opt back into 90% sizing)" {
  cat >"$STUB/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FIX/sent.log"
SH
  chmod +x "$STUB/herdr"
  export HERDR_BIN_PATH="$STUB/herdr"
  QUICKLOOK_OPEN_PLACEMENT=popup run bash "$ROOT/scripts/open-popup.sh" 'src/target.md'
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6; do [ -f "$FIX/sent.log" ] && break; sleep 0.3; done
  grep -q -- '--placement popup' "$FIX/sent.log"
  grep -q -- '90%' "$FIX/sent.log"
}

@test "open-popup honors QUICKLOOK_OPEN_PLACEMENT=tab (full pane, no size flags)" {
  cat >"$STUB/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FIX/sent.log"
SH
  chmod +x "$STUB/herdr"
  export HERDR_BIN_PATH="$STUB/herdr"
  QUICKLOOK_OPEN_PLACEMENT=tab run bash "$ROOT/scripts/open-popup.sh" 'src/target.md'
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6; do [ -f "$FIX/sent.log" ] && break; sleep 0.3; done
  grep -q -- '--placement tab' "$FIX/sent.log"
  ! grep -q -- '--width' "$FIX/sent.log"
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

# ---- picks taken from INSIDE a preview (QUICKLOOK_ORIGIN_PREVIEW=1) ----
# The origin preview is an overlay, and two overlays in one tab do not stack,
# so anything spawned by such a pick must go to the popup surface or it
# renders invisibly behind the origin. A file token never spawns at all: it
# pushes onto the origin's stack with :e.

# The push's send-text/send-keys calls are >/dev/null by design, so a stub
# that echoes argv proves nothing here; it records to a marker file instead.
@test "preview-origin pick: a FILE token pushes into the origin pane, spawns nothing" {
  cat >"$STUB/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FIX/sent.log"
SH
  chmod +x "$STUB/herdr"
  export HERDR_BIN_PATH="$STUB/herdr"
  cd "$FIX/repo"
  QUICKLOOK_ORIGIN_PREVIEW=1 QUICKLOOK_ORIGIN_PANE=p-org QUICKLOOK_ORIGIN_CWD="$FIX/repo" \
    run bash "$ROOT/scripts/open-popup.sh" 'src/target.md'
  [ "$status" -eq 0 ]
  grep -q "pane send-text p-org :e $FIX/repo/src/target.md" "$FIX/sent.log"
  grep -q "pane send-keys p-org Enter" "$FIX/sent.log"
  ! grep -q "pane open" "$FIX/sent.log"
}

# The spawn is DETACHED (ignores HUP, fds off the pty) because it outlives
# the closing hint pane; stdout proves nothing, so the stub records argv to a
# file and the assertions wait for the detached write.
@test "preview-origin pick: a NON-FILE token falls back to the POPUP surface, never an overlay" {
  cat >"$STUB/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FIX/sent.log"
SH
  chmod +x "$STUB/herdr"
  export HERDR_BIN_PATH="$STUB/herdr"
  QUICKLOOK_ORIGIN_PREVIEW=1 QUICKLOOK_ORIGIN_PANE=p-org QUICKLOOK_ORIGIN_CWD="$FIX/repo" \
    run bash "$ROOT/scripts/open-popup.sh" 'https://example.test/x'
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6; do [ -f "$FIX/sent.log" ] && break; sleep 0.3; done
  grep -q -- '--placement popup' "$FIX/sent.log"
  ! grep -q -- '--placement overlay' "$FIX/sent.log"
  grep -q -- '90%' "$FIX/sent.log"
}

@test "preview-origin pick: an EXPLICIT tab placement still wins over the popup fallback" {
  cat >"$STUB/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$FIX/sent.log"
SH
  chmod +x "$STUB/herdr"
  export HERDR_BIN_PATH="$STUB/herdr"
  QUICKLOOK_ORIGIN_PREVIEW=1 QUICKLOOK_ORIGIN_PANE=p-org QUICKLOOK_ORIGIN_CWD="$FIX/repo" \
    QUICKLOOK_OPEN_PLACEMENT=tab \
    run bash "$ROOT/scripts/open-popup.sh" 'https://example.test/x'
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6; do [ -f "$FIX/sent.log" ] && break; sleep 0.3; done
  grep -q -- '--placement tab' "$FIX/sent.log"
  ! grep -q -- '--placement popup' "$FIX/sent.log"
}
