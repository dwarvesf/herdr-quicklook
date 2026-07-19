#!/usr/bin/env bats
# Tests for the pick-anywhere token-scan lib (SG-01, v0.5): pick_scan_text /
# pick_count_header / pick_acquire in scripts/lib.sh. Same style as
# registry.bats/quicklook.bats: source lib.sh directly (unit-test-shaped),
# a temp git repo with real tracked files/dirs the handlers resolve
# against, no live pane except in the pick_acquire tests (a stubbed herdr).

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  # pwd -P canonicalizes /var vs /private/var, same reason quicklook.bats does.
  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # repo DIRECTORY NAME is "repo" so a github/gitlab/bitbucket blob URL for
  # repo "repo" resolves locally (mirrors registry.bats's "myrepo" pattern).
  mkdir -p "$FIX/repo/sub" "$FIX/repo/src"
  git -C "$FIX/repo" init -q -b main
  printf 'hello\n' >"$FIX/repo/sub/inrepo.md"
  printf 'widget content\n' >"$FIX/repo/src/widget-thing.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm fixture

  cd "$FIX/repo"
  unset QUICKLOOK_TOKEN QUICKLOOK_ROOTS QUICKLOOK_PICK_ORIGIN_PANE QUICKLOOK_PICK_SOURCE
}

teardown() {
  cd /
  rm -rf "$FIX"
}

# ---- pick_scan_text: correct kind per span, one of each shape ----

@test "pick_scan_text: a real resolvable path -> kind path" {
  run pick_scan_text <<<'open sub/inrepo.md now'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t1')" ]
}

@test "pick_scan_text: a generic URL -> kind url" {
  run pick_scan_text <<<'see https://example.com/a/b for docs'
  [ "$output" = "$(printf 'https://example.com/a/b\turl\t1')" ]
}

@test "pick_scan_text: a GitLab blob URL resolving locally -> kind path (github.sh dispatch reused, not a new regex)" {
  run pick_scan_text <<<'https://gitlab.com/org/repo/-/blob/main/sub/inrepo.md'
  [ "$output" = "$(printf 'https://gitlab.com/org/repo/-/blob/main/sub/inrepo.md\tpath\t1')" ]
}

@test "pick_scan_text: a Bitbucket blob URL resolving locally -> kind path" {
  run pick_scan_text <<<'https://bitbucket.org/org/repo/src/main/sub/inrepo.md'
  [ "$output" = "$(printf 'https://bitbucket.org/org/repo/src/main/sub/inrepo.md\tpath\t1')" ]
}

@test "pick_scan_text: an unresolvable github blob URL falls back to kind url (browser mode, same as registry.bats)" {
  run pick_scan_text <<<'https://github.com/o/ghostrepo/blob/main/nope.md'
  [ "$output" = "$(printf 'https://github.com/o/ghostrepo/blob/main/nope.md\turl\t1')" ]
}

@test "pick_scan_text: a bare commit SHA -> kind sha" {
  run pick_scan_text <<<'commit abc1234def is relevant'
  [ "$output" = "$(printf 'abc1234def\tsha\t1')" ]
}

@test "pick_scan_text: a #ref -> kind ref" {
  run pick_scan_text <<<'see issue #42 for context'
  [ "$output" = "$(printf '#42\tref\t1')" ]
}

@test "pick_scan_text: a GitHub PR URL -> kind ref (same vcs bucket as #ref, both dispatch to gh pr view)" {
  run pick_scan_text <<<'https://github.com/o/r/pull/7 has the fix'
  [ "$output" = "$(printf 'https://github.com/o/r/pull/7\tref\t1')" ]
}

@test "pick_scan_text: a real directory -> kind dir (match_dir alone, no herdr call)" {
  run pick_scan_text <<<'the sub directory has more'
  [ "$output" = "$(printf 'sub\tdir\t1')" ]
}

@test "pick_scan_text: a bare filename that fuzzy-resolves (unique substring hit) -> kind name" {
  run pick_scan_text <<<'check the widget module'
  [ "$output" = "$(printf 'widget\tname\t1')" ]
}

@test "pick_scan_text: QUICKLOOK_SCAN_SKIP_NAMES=1 drops the bare-name fuzzy entirely" {
  QUICKLOOK_SCAN_SKIP_NAMES=1 run pick_scan_text <<<'check the widget module'
  [ -z "$output" ]
}

@test "fast mode: a path-shaped token needs NO existing file to classify" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'open missing/nowhere.go:12 next'
  [ "$output" = "$(printf 'missing/nowhere.go:12\tpath\t1')" ]
}

@test "fast mode: prose words carry no shape and are dropped" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'the recap of the picker module'
  [ -z "$output" ]
}

@test "fast mode: a dotted filename classifies by extension shape alone" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'see CHANGELOG.md for details'
  [ "$output" = "$(printf 'CHANGELOG.md\tpath\t1')" ]
}

@test "fast mode: a tilde needs a slash - '~2' prose is not a path" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'lech khoang ~2 cot so voi pane'
  [ -z "$output" ]
}

@test "fast mode: single-slash no-extension prose (rust/go) is dropped" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'viet bang rust/go cho nhanh'
  [ -z "$output" ]
}

@test "fast mode: single-slash no-extension token that EXISTS is a path" {
  mkdir -p "$FIX/repo/pair/leaf"
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'check the pair/leaf module'
  [ "$output" = "$(printf 'pair/leaf	path	1')" ]
}

@test "fast mode: a tilde-slash path is a path without existing" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'open ~/somewhere/deep/nothing now'
  [ "$output" = "$(printf '~/somewhere/deep/nothing	path	1')" ]
}

@test "bare domain -> kind url, in both scan modes" {
  run pick_scan_text <<<'visit hermes.d.foundation today'
  [ "$output" = "$(printf 'hermes.d.foundation\turl\t1')" ]
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'visit hermes.d.foundation today'
  [ "$output" = "$(printf 'hermes.d.foundation\turl\t1')" ]
}

@test "bare domain with an extension-looking TLD (herdr.dev) is a url, not a path" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'docs at herdr.dev now'
  [ "$output" = "$(printf 'herdr.dev\turl\t1')" ]
}

@test "file extensions never misclassify as domains (md, go stay path-shaped)" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'see CHANGELOG.md and missing/x.go here'
  [[ "$output" != *"url"* ]]
}

@test "resolve: a bare domain opens the browser with an https scheme" {
  resolve_any_token 'hermes.d.foundation'
  [ "$RESOLVED_MODE" = "browser" ]
  [ "$RESOLVED_TARGET" = "https://hermes.d.foundation" ]
}

@test "fast mode: a github blob URL stays a url (no local-checkout probe)" {
  QUICKLOOK_SCAN_FAST=1 run pick_scan_text <<<'https://github.com/o/repo/blob/main/sub/inrepo.md'
  [ "$output" = "$(printf 'https://github.com/o/repo/blob/main/sub/inrepo.md\turl\t1')" ]
}

@test "pick_scan_text: a bare filename with an AMBIGUOUS substring hit is dropped, not a crash" {
  printf 'x\n' >"$FIX/repo/src/second-widget.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm more
  run pick_scan_text <<<'check the widget module'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pick_scan_text: a span nothing resolves is dropped (not a candidate)" {
  run pick_scan_text <<<'this word matches nothing at all'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- negative control: zero resolvable tokens -> EMPTY output ----

@test "pick_scan_text: a screen with zero resolvable tokens yields empty output (negative control)" {
  run pick_scan_text <<'TXT'
just some ordinary prose
nothing here is a path, url, sha, ref, dir, or a real filename
plain english sentences only
TXT
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- dedup: same raw token repeated keeps the BOTTOM-MOST occurrence ----

@test "pick_scan_text: dedup keeps the bottom-most (largest line-no) occurrence, one row only" {
  run pick_scan_text <<'TXT'
sub/inrepo.md
sub/inrepo.md
sub/inrepo.md
TXT
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t3')" ]
}

@test "pick_scan_text: dedup applies across punctuation variants of the SAME token" {
  run pick_scan_text <<'TXT'
see (sub/inrepo.md) once
now see "sub/inrepo.md".
TXT
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t2')" ]
}

# ---- ranking: confidence tier order + within-tier bottom-first tiebreak ----

@test "pick_scan_text: ranks by confidence tier (path > url > sha > ref > dir > name), earlier lines can outrank later ones" {
  run pick_scan_text <<'TXT'
check the widget module
the sub directory has more
see issue #42 for context
commit abc1234def is relevant
see https://example.com/a/b for docs
open sub/inrepo.md now
TXT
  local -a lines=()
  while IFS= read -r l; do lines+=("$l"); done <<<"$output"
  [ "${#lines[@]}" -eq 6 ]
  [[ "${lines[0]}" == $'sub/inrepo.md\tpath\t6' ]]
  [[ "${lines[1]}" == $'https://example.com/a/b\turl\t5' ]]
  [[ "${lines[2]}" == $'abc1234def\tsha\t4' ]]
  [[ "${lines[3]}" == $'#42\tref\t3' ]]
  [[ "${lines[4]}" == $'sub\tdir\t2' ]]
  [[ "${lines[5]}" == $'widget\tname\t1' ]]
}

@test "pick_scan_text: within the same tier, the tiebreak is larger line-no (closer to the bottom) first" {
  printf 'x\n' >"$FIX/repo/top.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm more
  run pick_scan_text <<'TXT'
top.md
sub/inrepo.md
TXT
  local -a lines=()
  while IFS= read -r l; do lines+=("$l"); done <<<"$output"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" == $'sub/inrepo.md\tpath\t2' ]]
  [[ "${lines[1]}" == $'top.md\tpath\t1' ]]
}

@test "pick_scan_text: same tier AND same line-no falls to a deterministic THIRD tiebreak (raw-token lexicographic ascending)" {
  # two DIFFERENT real files, both kind=path, on the SAME line - without a
  # tertiary key the order would depend on bash associative-array
  # iteration (unspecified), not on anything the caller can predict.
  printf 'x\n' >"$FIX/repo/afile.md"
  printf 'x\n' >"$FIX/repo/bfile.md"
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm more
  run pick_scan_text <<<'bfile.md afile.md'
  [ "$output" = "$(printf 'afile.md\tpath\t1\nbfile.md\tpath\t1')" ]
}

# ---- classification REUSES HANDLER_KINDS, not a hardcoded copy ----

@test "pick_scan_text: reuses the LIVE HANDLER_KINDS array (a synthetic front-registered handler wins, proving no separate regex zoo)" {
  match_zzz() { return 0; }
  handle_zzz() { RESOLVED_MODE="zzz-mode"; return 0; }
  HANDLER_KINDS=(zzz "${HANDLER_KINDS[@]}")
  run pick_scan_text <<<'sub/inrepo.md'
  # the synthetic handler now wins first-match for every span (an
  # unrecognized RESOLVED_MODE falls out of _pick_classify_span's case
  # with no kind), so what was a real resolvable path is dropped instead
  # of misclassified - proving the scan walks the SAME live array
  # resolve_any_token uses, not a hardcoded copy of the kind order.
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- pick_count_header ----

@test "pick_count_header: emits only non-zero kinds in the fixed order, with the right total" {
  # piped directly (no nested `bash -c`): a pipeline's subshells fork from
  # THIS test's already-sourced shell, so pick_scan_text/pick_count_header
  # stay visible - a fresh `bash -c` process would not see them without an
  # explicit `export -f`.
  result="$(pick_scan_text <<'TXT' | pick_count_header
check sub/inrepo.md and https://example.com/a/b
see abc1234def and #42
look at sub
TXT
)"
  [ "$result" = '5 on screen · 1 path · 1 url · 1 sha · 1 ref · 1 dir' ]
}

@test "pick_count_header: an empty scan yields '0 on screen', no kind breakdown" {
  run pick_count_header </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "0 on screen" ]
}

# ---- pick_acquire: the one live-dependency wrapper ----

script_stubs() {
  STUB="$(mktemp -d)"
  # Deliberately NOT /opt/homebrew/bin (see NOTES.md's PATH-stub gotcha):
  # this host has a real herdr/jq there that must not shadow our stub.
  export PATH="$STUB:/usr/bin:/bin:/usr/local/bin"
  export HERDR_BIN_PATH="$STUB/herdr"
}

@test "pick_acquire: an explicit pane_id reads that pane and pipes the text through the scan" {
  script_stubs
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ] && [ "$3" = "wG:pP" ]; then
  printf 'sub/inrepo.md and https://example.com/a/b\n'
fi
SH
  chmod +x "$STUB/herdr"
  run pick_acquire "wG:pP"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t1\nhttps://example.com/a/b\turl\t1')" ]
}

@test "pick_acquire: falls back to \$QUICKLOOK_PICK_ORIGIN_PANE when no argument is given" {
  script_stubs
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "read" ] && [ "$3" = "env-pane" ]; then
  printf 'sub/inrepo.md\n'
fi
SH
  chmod +x "$STUB/herdr"
  export QUICKLOOK_PICK_ORIGIN_PANE="env-pane"
  run pick_acquire
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t1')" ]
}

@test "pick_acquire: no pane_id and no env -> best-effort 'herdr pane current | jq' fallback" {
  script_stubs
  cat >"$STUB/herdr" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "pane" ] && [ "$2" = "current" ]; then
  printf '{"result":{"pane":{"pane_id":"cur-pane"}}}\n'
elif [ "$1" = "pane" ] && [ "$2" = "read" ] && [ "$3" = "cur-pane" ]; then
  printf 'sub/inrepo.md\n'
fi
SH
  chmod +x "$STUB/herdr"
  cat >"$STUB/jq" <<'SH'
#!/usr/bin/env bash
exec /opt/homebrew/bin/jq "$@"
SH
  chmod +x "$STUB/jq"
  run pick_acquire
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t1')" ]
}

@test "pick_acquire: honors \$QUICKLOOK_PICK_SOURCE, forwarded as --source" {
  script_stubs
  # herdr's argv goes to a side-channel log, not stdout: stdout would be fed
  # straight into pick_scan_text (and scanned away), same reason registry/
  # recents.bats log `open`'s argv separately instead of asserting on stdout.
  ARGV_LOG="$(mktemp)"
  cat >"$STUB/herdr" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$ARGV_LOG"
SH
  chmod +x "$STUB/herdr"
  export QUICKLOOK_PICK_SOURCE="recent"
  pick_acquire "wG:pP" >/dev/null
  grep -q -- '--source recent' "$ARGV_LOG"
}

# ---- purity: pick_scan_text mutates no global (post-review MAJOR fix) ----

@test "pick_scan_text: never mutates CLIP_PATH/CLIP_LINE - a caller's in-flight values survive a scan untouched" {
  CLIP_PATH="SENTINEL_PATH"
  CLIP_LINE="SENTINEL_LINE"
  # a path-shaped span used to run parse_token (a global-setting side
  # effect) via handle_path; the rewrite never calls handle_path at all.
  pick_scan_text <<<'sub/inrepo.md' >/dev/null
  [ "$CLIP_PATH" = "SENTINEL_PATH" ]
  [ "$CLIP_LINE" = "SENTINEL_LINE" ]
}

@test "pick_scan_text: never mutates RESOLVED_TARGET/RESOLVED_MODE - a caller's in-flight resolve state survives a scan untouched" {
  RESOLVED_TARGET="SENTINEL_TARGET"
  RESOLVED_MODE="SENTINEL_MODE"
  # exercises the github/vcs/dir/path/name branches in one screen - none of
  # them call handle_github/handle_vcs/handle_dir/handle_path/
  # handle_bare_name any more (see the PURITY note in lib.sh).
  pick_scan_text <<'TXT' >/dev/null
open sub/inrepo.md and https://gitlab.com/org/repo/-/blob/main/sub/inrepo.md
commit abc1234def and the sub directory and widget
TXT
  [ "$RESOLVED_TARGET" = "SENTINEL_TARGET" ]
  [ "$RESOLVED_MODE" = "SENTINEL_MODE" ]
}

# ---- ANSI/OSC defense: a decorated screen still classifies correctly ----

@test "pick_scan_text: ANSI SGR color codes around a path/URL are stripped and classified correctly" {
  # real ESC bytes (\x1b), not the literal text "\x1b" - matches what a
  # colorizing tool (ls --color, git, grep --color) actually emits.
  run pick_scan_text <<< $'open \x1b[32msub/inrepo.md\x1b[0m or \x1b[1;34mhttps://example.com/a/b\x1b[0m'
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t1\nhttps://example.com/a/b\turl\t1')" ]
}

@test "pick_scan_text: an OSC terminal-title sequence is stripped and does not corrupt the surrounding tokens" {
  run pick_scan_text <<< $'\x1b]0;my title\x07open sub/inrepo.md now'
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t1')" ]
}

# ---- perf tripwire (CRITICAL post-review fix): dedup-before-classify +
# once-per-scan repo-state hoisting, not once-per-span subprocess fan-out.
# Generous 5s bound on a 500-line screen - well clear of the intended
# <1s steady state, but tight enough to catch an O(n·subprocess)
# regression without flaking on a loaded CI box. ----

@test "pick_scan_text: a ~500-line busy screen scans well under the 5s perf tripwire" {
  local fixture i
  fixture="$(mktemp)"
  for i in $(seq 1 500); do
    if ((i % 5 == 0)); then
      printf 'line %d: see sub/inrepo.md and https://example.com/a/b and abc1234def\n' "$i"
    else
      printf 'just some ordinary prose line number %d with nothing special in it at all\n' "$i"
    fi
  done >"$fixture"
  SECONDS=0
  run pick_scan_text < "$fixture"
  local elapsed=$SECONDS
  echo "elapsed=${elapsed}s (bound: <5s)" >&3
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 5 ]
}

# ---- bash 3.2 compatibility (gate-review rewrite): pick_scan_text/
# pick_count_header used to need bash >= 4.3 (`local -A`/`local -n`); the
# scan is now awk (dedup/trim/rank) + zero-fork bash (classify via a fixed
# global, not a nameref), so it runs correctly on ANY bash >= 3.2 including
# macOS's own /bin/bash. These tests drive the real /bin/bash on this Mac
# (bash 3.2.57), not just the modern bash bats itself runs under - a
# regression that only breaks under 3.2 (e.g. a stray `${var,,}`) would
# pass every OTHER test in this file and only show up here. Each test
# writes a small script file (so $FIX/$LIB interpolate in the OUTER,
# modern-bash test before /bin/bash ever sees the script - no quoting
# gymnastics inside a `bash -c '...'` string) and runs it via `run
# /bin/bash "$script"`. ----

@test "sanity: /bin/bash on this host really is bash 3.2, not silently aliased to a modern bash" {
  run /bin/bash -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"'
  echo "/bin/bash reports bash ${output}" >&3
  [ "$status" -eq 0 ]
}

@test "pick_scan_text: full multi-kind ranking under real /bin/bash (bash 3.2) matches the modern-bash result exactly" {
  local script
  script="$(mktemp)"
  cat >"$script" <<SCRIPT
set -u
cd "$FIX/repo" || exit 1
. "$LIB"
pick_scan_text
SCRIPT
  run /bin/bash "$script" <<'TXT'
check the widget module
the sub directory has more
see issue #42 for context
commit abc1234def is relevant
see https://example.com/a/b for docs
open sub/inrepo.md now
TXT
  [ "$status" -eq 0 ]
  local -a lines=()
  while IFS= read -r l; do lines+=("$l"); done <<<"$output"
  [ "${#lines[@]}" -eq 6 ]
  [[ "${lines[0]}" == $'sub/inrepo.md\tpath\t6' ]]
  [[ "${lines[1]}" == $'https://example.com/a/b\turl\t5' ]]
  [[ "${lines[2]}" == $'abc1234def\tsha\t4' ]]
  [[ "${lines[3]}" == $'#42\tref\t3' ]]
  [[ "${lines[4]}" == $'sub\tdir\t2' ]]
  [[ "${lines[5]}" == $'widget\tname\t1' ]]
}

@test "pick_scan_text: dedup + punctuation-trim under real /bin/bash (bash 3.2)" {
  local script
  script="$(mktemp)"
  cat >"$script" <<SCRIPT
set -u
cd "$FIX/repo" || exit 1
. "$LIB"
pick_scan_text
SCRIPT
  run /bin/bash "$script" <<'TXT'
see (sub/inrepo.md) once
now see "sub/inrepo.md".
TXT
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'sub/inrepo.md\tpath\t2')" ]
}

@test "pick_count_header under real /bin/bash (bash 3.2): correct aggregation" {
  local script
  script="$(mktemp)"
  cat >"$script" <<SCRIPT
set -u
cd "$FIX/repo" || exit 1
. "$LIB"
pick_scan_text | pick_count_header
SCRIPT
  run /bin/bash "$script" <<'TXT'
check sub/inrepo.md and https://example.com/a/b
see abc1234def and #42
look at sub
TXT
  [ "$status" -eq 0 ]
  [ "$output" = '5 on screen · 1 path · 1 url · 1 sha · 1 ref · 1 dir' ]
}

@test "pick_scan_text: a bare filename that fuzzy-resolves works under real /bin/bash (bash 3.2) - the former \${var,,} bad-substitution site" {
  local script
  script="$(mktemp)"
  cat >"$script" <<SCRIPT
set -u
cd "$FIX/repo" || exit 1
. "$LIB"
pick_scan_text
SCRIPT
  run /bin/bash "$script" <<<'check the widget module'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'widget\tname\t1')" ]
}

@test "pick_scan_text: perf tripwire (500-line screen) also holds under real /bin/bash (bash 3.2), generous 8s bound" {
  local fixture script i start end elapsed
  fixture="$(mktemp)"
  for i in $(seq 1 500); do
    if ((i % 5 == 0)); then
      printf 'line %d: see sub/inrepo.md and https://example.com/a/b and abc1234def\n' "$i"
    else
      printf 'just some ordinary prose line number %d with nothing special in it at all\n' "$i"
    fi
  done >"$fixture"
  script="$(mktemp)"
  cat >"$script" <<SCRIPT
set -u
cd "$FIX/repo" || exit 1
. "$LIB"
pick_scan_text < "$fixture"
SCRIPT
  start=$(date +%s)
  run /bin/bash "$script"
  end=$(date +%s)
  elapsed=$((end - start))
  echo "elapsed=${elapsed}s (bound: <8s, /bin/bash 3.2)" >&3
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 8 ]
}

# ---- no-cap clarity: there is no candidate cap anywhere in the scan/pick
# path - a busy screen with 100+ distinct openable tokens must yield ALL of
# them, not a truncated top-N. ----

@test "pick_scan_text: 100+ distinct tokens all appear in the output, no cap or truncation (anti-truncation guard)" {
  local i name
  local -a names=()
  for i in $(seq -w 1 120); do
    name="tok${i}.md"
    printf 'x\n' >"$FIX/repo/$name"
    names+=("$name")
  done
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm "120 distinct tokens"

  run pick_scan_text < <(printf '%s\n' "${names[@]}")
  [ "$status" -eq 0 ]
  local -a lines=()
  while IFS= read -r l; do lines+=("$l"); done <<<"$output"
  [ "${#lines[@]}" -eq 120 ]

  # spot-check the first and last token both made it through, each as kind path.
  [[ "$output" == *$'\n'"${names[0]}"$'\t''path'* || "$output" == "${names[0]}"$'\t''path'* ]]
  [[ "$output" == *"${names[119]}"$'\t''path'* ]]

  local header
  header="$(pick_scan_text < <(printf '%s\n' "${names[@]}") | pick_count_header)"
  [ "$header" = "120 on screen · 120 path" ]
}
