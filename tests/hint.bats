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
  for i in 0 1 9 "$last"; do
    key="$(hint_key_for_index "$i")"
    [ -n "$key" ]
    [ "$(hint_index_for_key "$key")" = "$i" ]
  done
}

@test "the cancel key q is not a hint key" {
  run hint_index_for_key "q"
  [ "$status" -ne 0 ]
}

@test "workspace sweep: a relative path from ANOTHER repo resolves via roots" {
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/root/repoA/sub" "$FIX/elsewhere"
  printf 'x\n' >"$FIX/root/repoA/sub/deep-file.md"
  cd "$FIX/elsewhere"
  QUICKLOOK_ROOTS="$FIX/root" resolve_any_token './sub/deep-file.md'
  [ "$RESOLVED_TARGET" = "$FIX/root/repoA/sub/deep-file.md" ]
  QUICKLOOK_ROOTS="$FIX/root" resolve_any_token 'sub/deep-file.md'
  [ "$RESOLVED_TARGET" = "$FIX/root/repoA/sub/deep-file.md" ]
  cd /; rm -rf "$FIX"
}

@test "workspace sweep: reaches another repo's house-standard worktrees" {
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/root/repoA/.claude/worktrees/wt1/demo" "$FIX/elsewhere"
  printf 'x\n' >"$FIX/root/repoA/.claude/worktrees/wt1/demo/artifact.gif"
  cd "$FIX/elsewhere"
  QUICKLOOK_ROOTS="$FIX/root" resolve_any_token 'demo/artifact.gif'
  [ "$RESOLVED_TARGET" = "$FIX/root/repoA/.claude/worktrees/wt1/demo/artifact.gif" ]
  cd /; rm -rf "$FIX"
}

@test "workspace sweep: a slash-less token never sweeps (no false hits)" {
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/root/repoA" "$FIX/elsewhere"
  printf 'x\n' >"$FIX/root/repoA/lonely.md"
  cd "$FIX/elsewhere"
  run bash -c ". '$BATS_TEST_DIRNAME/../scripts/lib.sh'; QUICKLOOK_ROOTS='$FIX/root' resolve_any_token 'lonely.md'"
  [ "$status" -ne 0 ]
  cd /; rm -rf "$FIX"
}

@test "resolve_any_token expands a tilde path to the user's home" {
  FIX="$(mktemp -d)"
  printf 'x\n' >"$FIX/tilde-fixture.md"
  HOME="$FIX" resolve_any_token '~/tilde-fixture.md'
  [ "$RESOLVED_MODE" != "browser" ]
  [[ "$RESOLVED_TARGET" == *"/tilde-fixture.md" ]]
  rm -rf "$FIX"
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

# The preview's bottom row is less's prompt (our key-hint footer), not
# document content. The scanner cannot tell, so it used to hand out hint
# letters for the footer's own text: the object name became a target, and the
# `/` in "/ search" became one that opens the FILESYSTEM ROOT in the viewer.
@test "strip_pager_footer drops the last non-blank row only" {
  run bash -c ". '$LIB'; printf 'alpha\nbravo\nfoot · q quit\n' | strip_pager_footer"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "alpha" ]
  [ "${lines[1]}" = "bravo" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "strip_pager_footer keeps rows above the footer at their original index" {
  # The overlay paints hints by line number against the UNstripped snapshot,
  # so only the footer row may vanish; every row above it must keep its index.
  run bash -c ". '$LIB'; printf 'a\n\nb\nfoot · q quit\n\n\n' | strip_pager_footer | sed -n '3p'"
  [ "$status" -eq 0 ]
  [ "$output" = "b" ]
}

@test "strip_pager_footer removes exactly one row" {
  run bash -c ". '$LIB'; printf 'a\n\nb\nfoot · q quit\n\n\n' | strip_pager_footer | wc -l | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]
}

@test "strip_pager_footer on empty input is a no-op" {
  run bash -c ". '$LIB'; printf '' | strip_pager_footer"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
