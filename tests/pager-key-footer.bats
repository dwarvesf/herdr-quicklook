#!/usr/bin/env bats
# The pager's key footer: every pager path advertises the SAME keys, and
# every key it advertises is really bound in ../lesskey (a footer that lies
# is worse than no footer). Opt-out via an empty QUICKLOOK_KEY_HINT.

setup() {
  export HERDR_BIN_PATH=/usr/bin/false
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  LESSKEY="$BATS_TEST_DIRNAME/../lesskey"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf 'plain text\n' > "$FIX/doc.txt"
  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nprintf "LESS_ARGS:%%s\\n" "$*"\ncat >/dev/null\n' > "$STUB/less"
  chmod +x "$STUB/less"
  export PATH="$STUB:/usr/bin:/bin"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

@test "pager_prompt_args: yields a less short-prompt flag carrying the hint" {
  pager_prompt_args
  [ "${#PAGER_PROMPT_ARGS[@]}" -eq 1 ]
  [[ "${PAGER_PROMPT_ARGS[0]}" == "-Ps"* ]]
  [[ "${PAGER_PROMPT_ARGS[0]}" == *"q quit"* ]]
}

@test "pager_prompt_args: an empty hint is the opt-out (no flag at all)" {
  QUICKLOOK_KEY_HINT=""
  pager_prompt_args
  [ "${#PAGER_PROMPT_ARGS[@]}" -eq 0 ]
}

@test "the footer never advertises a key that is not bound" {
  # o / e / D come from ../lesskey; q and / are less's own built-ins.
  grep -qE '^o visual' "$LESSKEY"
  grep -qE '^e pshell' "$LESSKEY"
  grep -qE '^D shell' "$LESSKEY"
  for k in o e D; do
    [[ "$QUICKLOOK_KEY_HINT" == *"$k "* ]]
  done
}

@test "render_command_in_pager passes the footer to less" {
  run render_command_in_pager printf 'hello\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"-Ps"* ]]
  [[ "$output" == *"o viewer"* ]]
}

@test "render_text passes the same footer to less" {
  run bash -c ". '$LIB'; render_text '$FIX/doc.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-Ps"* ]]
  [[ "$output" == *"o viewer"* ]]
}

@test "the hint carries no % so less prompt escapes cannot fire on it" {
  [[ "$QUICKLOOK_KEY_HINT" != *"%"* ]]
}
