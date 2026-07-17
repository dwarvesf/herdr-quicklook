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
