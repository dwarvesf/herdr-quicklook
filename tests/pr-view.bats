#!/usr/bin/env bats
# pr-view.sh's layout: a title row on top, empty gh fields dropped, a rule
# between metadata and body, and the body rendered as markdown by default.

setup() {
  export HERDR_BIN_PATH=/usr/bin/false
  PRVIEW="$BATS_TEST_DIRNAME/../scripts/pr-view.sh"
  STUB="$(mktemp -d)"

  # gh's real shape: `name<TAB>value`, empty fields still printed, then a
  # lone `--` before the markdown body.
  cat > "$STUB/gh" <<'GH'
#!/usr/bin/env bash
printf 'title:\tdocs: a capacity test plan\n'
printf 'state:\tMERGED\n'
printf 'author:\ttieubao (Han Ngo)\n'
printf 'labels:\t\n'
printf 'assignees:\t\n'
printf 'reviewers:\t\n'
printf 'projects:\t\n'
printf 'milestone:\t\n'
printf 'number:\t65\n'
printf 'url:\thttps://example.invalid/pull/65\n'
printf -- '--\n'
printf '# Summary\n\nBody text here.\n'
GH
  chmod +x "$STUB/gh"
  export PATH="$STUB:/usr/bin:/bin"
  unset QUICKLOOK_PR_RAW
}

teardown() {
  rm -rf "$STUB"
}

plain() { perl -pe 's/\e\[[0-9;]*m//g'; }

@test "pr-view: the title row names the PR on the FIRST line" {
  run bash -c "bash '$PRVIEW' 65 | perl -pe 's/\\e\\[[0-9;]*m//g' | head -1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR #65"* ]]
  [[ "$output" == *"a capacity test plan"* ]]
  [[ "$output" == *"[MERGED]"* ]]
}

@test "pr-view: gh's empty fields are dropped" {
  run bash -c "bash '$PRVIEW' 65 | perl -pe 's/\\e\\[[0-9;]*m//g'"
  [ "$status" -eq 0 ]
  for empty in labels assignees reviewers projects milestone; do
    [[ "$output" != *"$empty:"* ]]
  done
  # the fields that DO have values survive
  [[ "$output" == *"author:"* ]]
  [[ "$output" == *"url:"* ]]
}

@test "pr-view: title and state are not repeated below the header row" {
  run bash -c "bash '$PRVIEW' 65 | perl -pe 's/\\e\\[[0-9;]*m//g'"
  [[ "$output" != *"title:"* ]]
  [[ "$output" != *"state:"* ]]
}

@test "pr-view: a rule separates the metadata from the body" {
  run bash -c "bash '$PRVIEW' 65 | perl -pe 's/\\e\\[[0-9;]*m//g'"
  [[ "$output" == *"────"* ]]
  [[ "$output" == *"Body text here."* ]]
}

@test "pr-view: QUICKLOOK_PR_RAW prints gh's output verbatim" {
  QUICKLOOK_PR_RAW=1 run bash "$PRVIEW" 65
  [ "$status" -eq 0 ]
  # raw keeps the empty fields and the bare -- separator
  [[ "$output" == *"labels:"* ]]
  [[ "$output" == *"--"* ]]
  [[ "$output" != *"PR #65 ·"* ]]
}

@test "pr-view: no ref is a no-op, never a bare gh call" {
  run bash "$PRVIEW"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
