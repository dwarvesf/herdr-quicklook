#!/usr/bin/env bats
# Tests for scripts/renderers/csv.sh (csv/tsv via `qsv table`, v0.4
# SG-06/P2). Same fixture/sourcing shape as tests/render-registry.bats.
# `qsv` is not a base-system tool, so a plain /usr/bin:/bin PATH is a real
# absence (verified - no /opt/homebrew/bin or /usr/local/bin gotcha here).

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  printf 'a,b,c\n1,2,3\n' > "$FIX/t.csv"
  printf 'a\tb\tc\n1\t2\t3\n' > "$FIX/t.tsv"
  # binary garbage wearing a .csv/.tsv extension - the negative control,
  # same shape as render-registry.bats's own blob.bin.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.csv"
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.tsv"

  STUB="$(mktemp -d)"
  export QSV_ARGV_FILE="$FIX/qsv.argv"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

_stub_qsv() {
  cat > "$STUB/qsv" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$QSV_ARGV_FILE"
printf 'QSV_TABLE\n'
exit 0
SH
  chmod +x "$STUB/qsv"
}

# ---- match: qsv present ----

@test "match_render_csv: matches a real .csv when qsv is present" {
  _stub_qsv
  export PATH="$STUB:$PATH"
  match_render_csv "$FIX/t.csv"
}

@test "match_render_csv: matches a real .tsv when qsv is present" {
  _stub_qsv
  export PATH="$STUB:$PATH"
  match_render_csv "$FIX/t.tsv"
}

@test "match_render_csv: declines a non-csv/tsv extension" {
  _stub_qsv
  export PATH="$STUB:$PATH"
  printf 'hello\n' > "$FIX/t.md"
  ! match_render_csv "$FIX/t.md"
}

# ---- degrade: qsv absent ----

@test "match_render_csv: declines when qsv is absent (PATH excludes /opt/homebrew/bin and /usr/local/bin)" {
  export PATH="/usr/bin:/bin"
  ! command -v qsv >/dev/null 2>&1
  ! match_render_csv "$FIX/t.csv"
}

@test "render-registry: qsv absent - a real csv falls through to the text renderer, not fallback (a csv is still readable as text)" {
  export PATH="/usr/bin:/bin"
  run bash -c "
    . '$LIB'
    render_text() { printf 'TEXT-RENDERED:%s\n' \"\$1\"; return 0; }
    render_fallback() { printf 'FALLBACK-RENDERED:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.csv'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "TEXT-RENDERED:$FIX/t.csv" ]
}

# ---- negative control: type mismatch, not just extension ----

@test "match_render_csv: declines binary garbage renamed .csv/.tsv (keys on type, not extension)" {
  _stub_qsv
  export PATH="$STUB:$PATH"
  ! match_render_csv "$FIX/fake.csv"
  ! match_render_csv "$FIX/fake.tsv"
}

@test "render-registry: binary garbage renamed .csv routes to fallback, never qsv" {
  _stub_qsv
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.csv'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.csv" ]
  [ ! -e "$QSV_ARGV_FILE" ]
}

# ---- render: aligned table argv, csv default vs tsv explicit delimiter ----

@test "render_csv: a .csv calls qsv table with no explicit delimiter" {
  _stub_qsv
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_csv '$FIX/t.csv'"
  [ "$status" -eq 0 ]
  [ -f "$QSV_ARGV_FILE" ]
  grep -qx -- "$FIX/t.csv" "$QSV_ARGV_FILE"
  ! grep -qx -- '-d' "$QSV_ARGV_FILE"
  [[ "$output" == *"QSV_TABLE"* ]]
}

@test "render_csv: a .tsv calls qsv table with an explicit tab delimiter" {
  _stub_qsv
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_csv '$FIX/t.tsv'"
  [ "$status" -eq 0 ]
  [ -f "$QSV_ARGV_FILE" ]
  grep -qx -- '-d' "$QSV_ARGV_FILE"
  printf '\t' > "$FIX/tab.expected"
  grep -qxFf "$FIX/tab.expected" "$QSV_ARGV_FILE"
  grep -qx -- "$FIX/t.tsv" "$QSV_ARGV_FILE"
}

# ---- real qsv end-to-end (no stub): a genuine aligned table, not a stub echo ----

@test "render_csv: a real .csv renders an aligned table via the actual qsv binary" {
  run bash -c ". '$LIB'; render_csv '$FIX/t.csv'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a"*"b"*"c"* ]]
  [[ "$output" == *"1"*"2"*"3"* ]]
}
