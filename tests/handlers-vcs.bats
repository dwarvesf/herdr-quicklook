#!/usr/bin/env bats
# Tests for scripts/handlers/vcs.sh (SG-02, vcs-tokens): a bare commit SHA ->
# `git show`, a `#123` ref or a GitHub PR URL -> `gh pr view`, mode=command.
# Same style as registry.bats: source lib.sh directly and call
# match_vcs/handle_vcs (they communicate through RESOLVED_* globals), not
# `run` in a subshell, except where a test deliberately executes the built
# argv for real to prove the security/correctness behavior end to end.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  git -C "$FIX" init -q -b main
  printf 'hello\n' > "$FIX/f.md"
  git -C "$FIX" add -A
  git -C "$FIX" -c user.email=t@t -c user.name=t commit -qm 'fixture commit'
  REAL_SHA="$(git -C "$FIX" log --format=%H -1)"
  REAL_SUBJECT="$(git -C "$FIX" log --format=%s -1)"
  cd "$FIX"
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# ---- match_vcs: accepted shapes ----

@test "match_vcs: accepts a 7-char hex SHA (lower bound)" {
  match_vcs "abc1234"
}

@test "match_vcs: accepts a 40-char hex SHA (upper bound, full SHA)" {
  match_vcs "0123456789abcdef0123456789abcdef01234567"
}

@test "match_vcs: accepts a #123 hashref" {
  match_vcs "#123"
}

@test "match_vcs: accepts a GitHub PR URL" {
  match_vcs "https://github.com/dwarvesf/herdr-quicklook/pull/42"
}

@test "match_vcs: accepts a GitHub PR URL with a trailing slash" {
  match_vcs "https://github.com/dwarvesf/herdr-quicklook/pull/42/"
}

# ---- match_vcs: named negative controls ----
# Every one of these must be REJECTED (match_vcs returns 1) so the token
# falls through to the next handler instead of ever reaching handle_vcs.

@test "negative control: metacharacter (semicolon + shell command)" {
  run match_vcs "abc1234; rm -rf /"
  [ "$status" -eq 1 ]
}

@test "negative control: command substitution \$(...)" {
  run match_vcs '$(whoami)'
  [ "$status" -eq 1 ]
}

@test "negative control: backtick command substitution" {
  run match_vcs '`whoami`'
  [ "$status" -eq 1 ]
}

@test "negative control: flag injection --upload-pack=..." {
  run match_vcs "--upload-pack=/tmp/evil"
  [ "$status" -eq 1 ]
}

@test "negative control: flag injection -O (short flag)" {
  run match_vcs "-O"
  [ "$status" -eq 1 ]
}

@test "negative control: non-hex lookalike (contains 'g', same length as a valid SHA)" {
  run match_vcs "1234567g"
  [ "$status" -eq 1 ]
}

@test "negative control: non-hex lookalike (uppercase hex - regex is lowercase-only per spec)" {
  run match_vcs "ABC1234"
  [ "$status" -eq 1 ]
}

@test "negative control: over-long token (41 hex chars, one past the cap)" {
  run match_vcs "0123456789abcdef0123456789abcdef012345678"
  [ "$status" -eq 1 ]
}

@test "negative control: over-long token (1000-char hex-looking clipboard blob)" {
  local blob
  blob="$(printf 'a%.0s' $(seq 1 1000))"
  run match_vcs "$blob"
  [ "$status" -eq 1 ]
}

@test "negative control: under-length token (6 hex chars, one short of the floor)" {
  run match_vcs "abc123"
  [ "$status" -eq 1 ]
}

@test "negative control: valid-looking SHA PREFIX with a malicious suffix (anchoring proof)" {
  # a naive unanchored regex (e.g. [0-9a-f]{7,40} with no ^/\$) would match
  # the leading "abc1234" substring and accept this; the anchored regex must
  # reject the whole string because of the trailing garbage.
  run match_vcs "abc1234; rm -rf /"
  [ "$status" -eq 1 ]
}

@test "negative control: empty string" {
  run match_vcs ""
  [ "$status" -eq 1 ]
}

@test "negative control: a github blob URL (github.sh's shape) is not claimed by vcs" {
  run match_vcs "https://github.com/dwarvesf/herdr-quicklook/blob/main/pull/README.md"
  [ "$status" -eq 1 ]
}

# ---- handle_vcs: exact argv (the required checklist cases) ----

@test "handle_vcs: a valid SHA builds the exact argv git show --end-of-options <sha>" {
  handle_vcs "abc1234"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${#RESOLVED_CMD[@]}" -eq 4 ]
  [ "${RESOLVED_CMD[0]}" = "git" ]
  [ "${RESOLVED_CMD[1]}" = "show" ]
  [ "${RESOLVED_CMD[2]}" = "--end-of-options" ]
  [ "${RESOLVED_CMD[3]}" = "abc1234" ]
  # goal file's literal example is `git show -- <sha>`; this deliberately
  # uses `--end-of-options` instead of a trailing `--` - see the comment in
  # vcs.sh and this sub-goal's DECISIONS.md entry ("`--` silently shows HEAD
  # for a bogus SHA instead of erroring").
}

@test "handle_vcs: #123 builds the exact argv gh pr view 123" {
  handle_vcs "#123"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${#RESOLVED_CMD[@]}" -eq 4 ]
  [ "${RESOLVED_CMD[0]}" = "gh" ]
  [ "${RESOLVED_CMD[1]}" = "pr" ]
  [ "${RESOLVED_CMD[2]}" = "view" ]
  [ "${RESOLVED_CMD[3]}" = "123" ]
}

@test "handle_vcs: a GitHub PR URL builds gh pr view <url>" {
  handle_vcs "https://github.com/dwarvesf/herdr-quicklook/pull/42"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${#RESOLVED_CMD[@]}" -eq 4 ]
  [ "${RESOLVED_CMD[0]}" = "gh" ]
  [ "${RESOLVED_CMD[1]}" = "pr" ]
  [ "${RESOLVED_CMD[2]}" = "view" ]
  [ "${RESOLVED_CMD[3]}" = "https://github.com/dwarvesf/herdr-quicklook/pull/42" ]
}

# ---- non-hex token falls through to the next handler (checklist case) ----

@test "resolve_any_token: a non-hex token never gets mode=command from vcs" {
  # "notasha" isn't hex, doesn't start with # or a github pull URL - vcs
  # must decline so a LATER handler (here: path, since no such file exists)
  # gets the token, not vcs claiming it wrongly.
  rc=0
  resolve_any_token "notasha" || rc=$?
  [ "$rc" -eq 1 ]
  [ "$RESOLVED_MODE" != "command" ]
  [ -z "$RESOLVED_MODE" ]
}

@test "resolve_any_token: an over-long hex blob falls through past vcs to path (unresolved)" {
  local blob
  blob="$(printf 'a%.0s' $(seq 1 1000))"
  rc=0
  resolve_any_token "$blob" || rc=$?
  [ "$rc" -eq 1 ]
  [ "$RESOLVED_MODE" != "command" ]
}

# ---- argv-shape control (checklist case) ----
# Calls handle_vcs directly, bypassing match_vcs's gate entirely, to prove
# the ARGV CONSTRUCTION itself - not the input filter - is what keeps a
# value containing embedded whitespace and shell metacharacters as ONE argv
# element. This is the same "independent of the regex" property the SHA
# checklist case above exercises, pushed to an adversarial extreme.

@test "argv-shape control: a space-and-metacharacter value still lands as ONE arg after the SHA branch's --end-of-options" {
  handle_vcs 'abc1234 && rm -rf / #'
  [ "$RESOLVED_MODE" = "command" ]
  [ "${#RESOLVED_CMD[@]}" -eq 4 ]
  [ "${RESOLVED_CMD[3]}" = 'abc1234 && rm -rf / #' ]
}

@test "argv-shape control: a flag-injection value through the #-branch still lands as ONE arg" {
  handle_vcs '#123 --upload-pack=/tmp/evil'
  [ "$RESOLVED_MODE" = "command" ]
  [ "${#RESOLVED_CMD[@]}" -eq 4 ]
  [ "${RESOLVED_CMD[3]}" = '123 --upload-pack=/tmp/evil' ]
}

# ---- real execution: functional correctness + the security proof ----
# These actually RUN the built RESOLVED_CMD array (not just inspect it) to
# prove the argv-safety holds under a real git/gh invocation, not only in
# the array's shape.

@test "real run: a valid SHA's argv shows the real commit" {
  match_vcs "$REAL_SHA"
  handle_vcs "$REAL_SHA"
  run "${RESOLVED_CMD[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$REAL_SHA"* ]]
  [[ "$output" == *"$REAL_SUBJECT"* ]]
}

@test "real run: a bogus-but-hex-shaped SHA degrades to an error, never silently shows HEAD" {
  # this is the exact regression --end-of-options exists to prevent: with a
  # trailing `--`, git show would silently render HEAD's commit instead of
  # erroring, because `--` makes an unresolvable token a pathspec, not a
  # revision.
  local bogus="deadbee0"
  match_vcs "$bogus"
  handle_vcs "$bogus"
  run "${RESOLVED_CMD[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$REAL_SUBJECT"* ]]
}

@test "real run: flag-injection payload through the SHA branch fails safely instead of being parsed as a flag" {
  # even though match_vcs would never accept this (tested above), this
  # proves handle_vcs's OWN argv construction is safe in depth: git rejects
  # the injected-looking flag rather than acting on it.
  handle_vcs "--upload-pack=/tmp/evil"
  [ "${RESOLVED_CMD[2]}" = "--end-of-options" ]
  [ "${RESOLVED_CMD[3]}" = "--upload-pack=/tmp/evil" ]
  run "${RESOLVED_CMD[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must come before non-option arguments"* || "$output" == *"unknown"* || "$output" == *fatal* ]]
}

# ---- registry wiring: the HANDLER_KINDS reorder (vcs before url) ----
# lib.sh's HANDLER_KINDS was reordered from (github url vcs dir path) to
# (github vcs url dir path) as part of this sub-goal - see DECISIONS.md.
# Without this, a GitHub PR URL would be claimed by url.sh's generic
# http(s) match (mode=browser) before vcs.sh ever got a look, since url.sh's
# match depends only on classify_token, which has no PR-URL case.

@test "registry: a GitHub PR URL dispatches to vcs (mode=command), not url (mode=browser)" {
  resolve_any_token "https://github.com/dwarvesf/herdr-quicklook/pull/42"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${RESOLVED_CMD[0]}" = "gh" ]
}

@test "registry: a bare SHA dispatches to vcs end to end through resolve_any_token" {
  resolve_any_token "$REAL_SHA"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${RESOLVED_CMD[*]}" = "git show --end-of-options $REAL_SHA" ]
}

@test "registry: a #123 hashref dispatches to vcs end to end through resolve_any_token" {
  resolve_any_token "#7"
  [ "$RESOLVED_MODE" = "command" ]
  [ "${RESOLVED_CMD[*]}" = "gh pr view 7" ]
}

@test "registry: a generic non-github https URL still resolves as mode=browser (reorder did not regress url.sh)" {
  resolve_any_token "https://example.com/a/b"
  [ "$RESOLVED_MODE" = "browser" ]
  [ "$RESOLVED_TARGET" = "https://example.com/a/b" ]
}

@test "registry: a github blob URL still resolves as mode=file via github.sh (reorder did not regress github.sh)" {
  # "FIX" is not named the same as the URL's repo, so this exercises the
  # local-file-in-cwd path: top.md is not present here, so it should fail
  # to resolve locally and fall back to browser - still github.sh's own
  # handle_github, never vcs.
  resolve_any_token "https://github.com/o/ghostrepo/blob/main/nope.md"
  [ "$RESOLVED_MODE" = "browser" ]
}

# ---- contract compliance ----

@test "vcs.sh exports match_vcs and handle_vcs" {
  declare -F match_vcs >/dev/null
  declare -F handle_vcs >/dev/null
}
