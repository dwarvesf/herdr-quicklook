#!/usr/bin/env bats
# Tests for lib.sh's `linkify`: the pager-side OSC-8 emitter that makes every
# path/URL-shaped span in a preview Ctrl+clickable through the same
# virtual-token transport hint-pane uses.
#
# The load-bearing property is the ENCODING: quicklook_token_from_link
# re-encodes and demands a byte-for-byte match before it hands a token back,
# so linkify's inline awk encoder must agree with jq's @uri exactly. Anything
# else silently refuses every link at click time.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"
  ESC=$'\033'
}

# uri_of <text> -> the first sentinel URI linkify emits for that text.
uri_of() {
  printf 'x %s x\n' "$1" | linkify \
    | awk -v esc="$ESC" '{
        s = index($0, esc "]8;;")
        if (!s) exit 1
        rest = substr($0, s + 5)
        print substr(rest, 1, index(rest, esc) - 1)
      }'
}

# ---- encoding parity with jq @uri (the click-path gate) ----

@test "linkify: the inline encoder is byte-identical to jq @uri" {
  for t in 'scripts/lib.sh' 'a/b.md:12' '~/x/y.md' 'docs/a+b.md'; do
    [ "$(uri_of "$t")" = "$(quicklook_link_uri "$t")" ]
  done
}

@test "linkify: an emitted link decodes back to the exact token" {
  for t in 'scripts/lib.sh' 'docs/x.md:9'; do
    [ "$(quicklook_token_from_link "$(uri_of "$t")")" = "$t" ]
  done
}

# The regression this guards: with `/` missing from the pattern's start class
# an absolute path matched from its SECOND character, so the link carried a
# relative `var/folders/...` and the click resolved against the wrong root.
@test "linkify: an absolute path is linked whole, leading slash included" {
  [ "$(quicklook_token_from_link "$(uri_of /var/folders/x/T/doc.md)")" = "/var/folders/x/T/doc.md" ]
}

# ---- pass-through safety ----

@test "linkify: prose with nothing openable is byte-identical" {
  run bash -c ". '$LIB'; printf 'just some words, nothing openable\n' | linkify"
  [ "$output" = "just some words, nothing openable" ]
}

@test "linkify: a line glow already hyperlinked is never nested into" {
  local already="${ESC}]8;;https://x.test${ESC}\\see docs/a.md${ESC}]8;;${ESC}\\"
  [ "$(printf '%s\n' "$already" | linkify)" = "$already" ]
}

@test "linkify: an SGR-coloured path keeps its colour and gains a link" {
  local out
  out="$(printf '%s\n' "${ESC}[31mscripts/lib.sh${ESC}[0m" | linkify)"
  [[ "$out" == *"${ESC}[31m"* ]]
  [[ "$out" == *"]8;;"* ]]
  [[ "$out" == *"${ESC}[0m"* ]]
}

# A text run holding no token leaves RLENGTH at -1; reading it after scan()
# made substr(line, 0) return the whole line and the awk loop never ended.
@test "linkify: an ANSI line whose text has no token terminates" {
  run timeout 20 bash -c ". '$LIB'; printf '${ESC}[1mplain words here${ESC}[0m\n' | linkify"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plain words here"* ]]
}

@test "linkify: QUICKLOOK_LINKIFY=0 is a pure pass-through" {
  run bash -c ". '$LIB'; printf 'see scripts/lib.sh\n' | QUICKLOOK_LINKIFY=0 linkify"
  [ "$output" = "see scripts/lib.sh" ]
}

# ---- no filesystem access (the perf contract that PR #23's linkify broke) ----

@test "linkify: links a path that does not exist (shape only, no resolve)" {
  run bash -c ". '$LIB'; printf 'see totally/absent/file.md\n' | linkify"
  [[ "$output" == *"]8;;"* ]]
}
