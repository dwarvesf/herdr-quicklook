#!/usr/bin/env bash
# Mutation sweep: are the tests actually watching, or just passing?
#
#   bash tests/mutation-sweep.sh                 # curated set
#   bash tests/mutation-sweep.sh linkify pad_left  # named functions
#   bash tests/mutation-sweep.sh --unmentioned     # list untested functions
#
# A green suite proves nothing on its own: a test can assert on something
# that cannot fail. This breaks a function on purpose and checks that some
# test NOTICES. A function that SURVIVES its mutation is either untested or
# covered only by non-discriminating assertions.
#
# That failure mode is not theoretical here. Two tests written during the
# stacked-preview work passed while asserting nothing: one keyed on the pager
# footer, which is painted once at pane start and never changes, so it would
# have passed on a complete no-op; the other keyed on a marker below the
# visible screenful, which `pane read --source visible` can never see.
#
# Mutation is applied by APPENDING an override that shadows the original.
# That needs no parsing of the function body and cannot corrupt the file the
# way an in-place edit could; lib.sh is restored from a byte copy after every
# run, including on interrupt.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
LIB=scripts/lib.sh
[ -f "$LIB" ] || { echo "run me from inside the repo" >&2; exit 1; }

# Default mutation body per function: enough to break it without breaking
# `source`. A filter becomes a passthrough, a producer goes silent, a
# predicate stops discriminating.
mutation_for() {
  case "$1" in
    linkify | pad_left | strip_pager_footer | pad_to_pane_height) printf 'cat;' ;;
    pane_cols | _pane_cols) printf 'printf 80;' ;;
    emit_supported | recents_path_is_safe | pane_is_preview | line_numbers_on) printf 'return 0;' ;;
    *) printf 'return 0;' ;;
  esac
}

if [ "${1:-}" = "--unmentioned" ]; then
  echo "Functions in $LIB that no test file even mentions:"
  while IFS= read -r f; do
    grep -q -- "$f" tests/*.bats 2>/dev/null || echo "  $f"
  done < <(grep -oE '^[a-z_]+\(\)' "$LIB" | sed 's/()//')
  exit 0
fi

BAK="$(mktemp)"
/bin/cp -f "$LIB" "$BAK"
restore() { /bin/cp -f "$BAK" "$LIB"; }
trap restore EXIT INT TERM

targets=("$@")
if [ "${#targets[@]}" -eq 0 ]; then
  targets=(strip_pager_footer linkify pane_cols emit_supported
    recents_path_is_safe pad_left quicklook_link_uri pick_scan_text parse_token)
fi

printf '%-26s %-9s %s\n' "FUNCTION" "VERDICT" "DETAIL"
printf '%-26s %-9s %s\n' "--------" "-------" "------"

status=0
for fn in "${targets[@]}"; do
  files="$(grep -l -- "$fn" tests/*.bats 2>/dev/null | tr '\n' ' ')"
  if [ -z "$files" ]; then
    printf '%-26s %-9s %s\n' "$fn" "NO-TESTS" "no test file mentions it"
    status=1
    continue
  fi
  printf '\n%s() { %s }\n' "$fn" "$(mutation_for "$fn")" >> "$LIB"
  # shellcheck disable=SC2086
  fails="$(timeout 300 bats $files 2>/dev/null | grep -c '^not ok')"
  restore
  if [ "${fails:-0}" -eq 0 ]; then
    printf '%-26s %-9s %s\n' "$fn" "SURVIVED" "mutation went unnoticed - the tests are not watching"
    status=1
  else
    printf '%-26s %-9s %s\n' "$fn" "killed" "$fails failing test(s)"
  fi
done

exit "$status"
