#!/usr/bin/env bats
# Script-level tests for escalate-editor.sh (the `e` -> $EDITOR hand-off).
# A stub editor script logs its argv, so we assert the exact command line
# built without invoking a real editor. Config precedence is exercised via a
# stub `herdr` binary answering `plugin config-dir` with a fixture dir that
# holds a `.env` (mirrors dispatch.bats' herdr-stub pattern).

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/escalate-editor.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  STUB="$(mktemp -d)"
  CFGDIR="$(mktemp -d)"

  printf 'line1\nline2\n' > "$FIX/f.md"
  printf 'target\n' > "$FIX/file with space.md"

  # editor stubs: each logs its OWN identity + argv, so a test can tell which
  # one actually ran (precedence) as well as the exact argv built.
  cat > "$STUB/env-editor" <<'SH'
#!/usr/bin/env bash
{ printf 'ENV ARGC:%d ARGS:' "$#"; for a in "$@"; do printf '[%s]' "$a"; done; printf '\n'; } >> "$STUB_LOG"
SH
  cat > "$STUB/cfg-editor" <<'SH'
#!/usr/bin/env bash
{ printf 'CFG ARGC:%d ARGS:' "$#"; for a in "$@"; do printf '[%s]' "$a"; done; printf '\n'; } >> "$STUB_LOG"
SH
  chmod +x "$STUB/env-editor" "$STUB/cfg-editor"

  # herdr stub: `plugin config-dir herdr-quicklook` prints CFGDIR (empty by
  # default, no .env -> load_config finds nothing, matching production when
  # no config file has been created)
  cat > "$STUB/herdr" <<SH
#!/usr/bin/env bash
if [ "\$1" = plugin ] && [ "\$2" = config-dir ]; then printf '%s\n' "$CFGDIR"; exit 0; fi
exit 0
SH
  chmod +x "$STUB/herdr"

  STUB_LOG="$FIX/editor.log"
  export STUB_LOG STUB
  export HERDR_BIN_PATH="$STUB/herdr"
  export PATH="$STUB:$PATH"
  unset QUICKLOOK_EDITOR EDITOR
}

teardown() {
  rm -rf "$FIX" "$STUB" "$CFGDIR"
}

@test "no line: builds \$EDITOR + file argv" {
  export EDITOR="$STUB/env-editor"
  run bash "$SCRIPT" "$FIX/f.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "ENV ARGC:1 ARGS:[$FIX/f.md]" ]
}

@test "+line: builds \$EDITOR +LINE file argv" {
  export EDITOR="$STUB/env-editor"
  run bash "$SCRIPT" "+5" "$FIX/f.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "ENV ARGC:2 ARGS:[+5][$FIX/f.md]" ]
}

@test "space-in-filename stays one arg" {
  export EDITOR="$STUB/env-editor"
  run bash "$SCRIPT" "+2" "$FIX/file with space.md"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "ENV ARGC:2 ARGS:[+2][$FIX/file with space.md]" ]
}

@test "config QUICKLOOK_EDITOR beats \$EDITOR" {
  printf 'QUICKLOOK_EDITOR="%s"\n' "$STUB/cfg-editor" > "$CFGDIR/.env"
  export EDITOR="$STUB/env-editor"
  run bash "$SCRIPT" "$FIX/f.md"
  [ "$status" -eq 0 ]
  # the CFG stub ran (config wins); the ENV stub never fired
  [ "$(cat "$STUB_LOG")" = "CFG ARGC:1 ARGS:[$FIX/f.md]" ]
}

@test "no file argument: exits quietly, no editor invoked" {
  export EDITOR="$STUB/env-editor"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
}
