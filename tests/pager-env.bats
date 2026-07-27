#!/usr/bin/env bats
# UTF-8 pager charset pins (see scripts/lib.sh). Own file: dispatch.bats's
# setup() rewires PATH/cwd, which broke relative sourcing here.

@test "pager env: sourcing lib.sh forces a UTF-8 charset for less" {
  run bash -c "unset LESSCHARSET LANG; . '$BATS_TEST_DIRNAME/../scripts/lib.sh'; printf %s::%s \"\$LESSCHARSET\" \"\$LANG\""
  [ "$status" -eq 0 ]
  [[ "$output" == "utf-8::en_US.UTF-8" ]]
}

@test "pager env: an explicit user locale is not clobbered" {
  run bash -c "export LESSCHARSET=latin1 LANG=fr_FR.UTF-8; . '$BATS_TEST_DIRNAME/../scripts/lib.sh'; printf %s::%s \"\$LESSCHARSET\" \"\$LANG\""
  [ "$status" -eq 0 ]
  [[ "$output" == "latin1::fr_FR.UTF-8" ]]
}

# Line numbers in the COMMAND pager: a csv/json/sqlite preview should match a
# markdown one when QUICKLOOK_LINE_NUMBERS=1. Numbers count the formatter's
# output rows (same caveat as glow's rendered rows).
@test "render_command_in_pager passes -N when line numbers are on" {
  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS:%%s\\n" "$*"\ncat >/dev/null\n' > "$STUB/less"
  chmod +x "$STUB/less"
  run bash -c "PATH='$STUB:/usr/bin:/bin'; QUICKLOOK_LINE_NUMBERS=1; . '$BATS_TEST_DIRNAME/../scripts/lib.sh'; render_command_in_pager printf 'x\n'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-N"* ]]
  run bash -c "PATH='$STUB:/usr/bin:/bin'; . '$BATS_TEST_DIRNAME/../scripts/lib.sh'; render_command_in_pager printf 'x\n'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"-N"* ]]
}
