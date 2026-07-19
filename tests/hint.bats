#!/usr/bin/env bats
# Pure-logic tests for the native hint picker's key<->index mapping (lib.sh).
# The overlay render + single-key capture is a TTY flow, verified by hand.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  LIB="$ROOT/scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"
}

@test "index 0 is the first home-row key" {
  run hint_key_for_index 0
  [ "$status" -eq 0 ]
  [ "$output" = "a" ]
}

@test "key <-> index round-trips across the whole range" {
  local i last=$(( ${#QUICKLOOK_HINT_KEYS} - 1 ))
  for i in 0 1 9 25 "$last"; do
    key="$(hint_key_for_index "$i")"
    [ -n "$key" ]
    [ "$(hint_index_for_key "$key")" = "$i" ]
  done
}

@test "index past the last key is rejected" {
  run hint_key_for_index "${#QUICKLOOK_HINT_KEYS}"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "non-numeric or empty index is rejected" {
  run hint_key_for_index "x"; [ "$status" -ne 0 ]
  run hint_key_for_index "";  [ "$status" -ne 0 ]
}

@test "a key outside the hint set is rejected" {
  run hint_index_for_key "1"; [ "$status" -ne 0 ]
  run hint_index_for_key "-"; [ "$status" -ne 0 ]
  run hint_index_for_key "";  [ "$status" -ne 0 ]
}

@test "every hint key is unique (no ambiguous label)" {
  uniq_count="$(printf '%s' "$QUICKLOOK_HINT_KEYS" | fold -w1 | sort -u | wc -l | tr -d ' ')"
  [ "$uniq_count" -eq "${#QUICKLOOK_HINT_KEYS}" ]
}
