#!/usr/bin/env bats
# Tests for scripts/renderers/sqlite.sh (v0.4 SG-07, P3 pack). Sources
# lib.sh directly, same fixture shape as tests/render-registry.bats.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # A real, minimal sqlite3 database (one table, two rows) - `file(1)`'s
  # sqlite detection needs genuine page-header structure, not just the
  # 16-byte magic string (verified: a magic-only fixture reports
  # application/octet-stream), so this is built with the real sqlite3 CLI.
  sqlite3 "$FIX/t.sqlite" "create table t(a int, b text); insert into t values (1,'x'),(2,'y');" >/dev/null
  cp "$FIX/t.sqlite" "$FIX/t.db"
  # binary garbage wearing a .sqlite/.db extension - the negative control.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.sqlite"
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.db"
  printf 'hello\n' > "$FIX/t.txt"

  # a stub sqlite3 that records its argv (order preserved), so render tests
  # can assert the invocation shape (readonly + schema/tables, never a
  # SELECT) without depending on real database content.
  STUB="$(mktemp -d)"
  cat > "$STUB/sqlite3" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SQLITE3_ARGV_FILE"
printf 'SQLITE3_DUMP\n'
exit 0
SH
  chmod +x "$STUB/sqlite3"
  export SQLITE3_ARGV_FILE="$FIX/sqlite3.argv"

  ONLYBASE="$(mktemp -d)"
  ln -s "$(command -v file)" "$ONLYBASE/file"
  ln -s "$(command -v tr)" "$ONLYBASE/tr"
  ln -s "$(command -v dirname)" "$ONLYBASE/dirname"
  ln -s "$(command -v bash)" "$ONLYBASE/bash"
}

teardown() {
  cd /
  /bin/rm -rf "$FIX" "$STUB" "$ONLYBASE"
  export PATH="/usr/bin:/bin:$PATH"
}

# ---- match: real sqlite db, both extensions ----

@test "match_render_sqlite: matches a real .sqlite database" {
  match_render_sqlite "$FIX/t.sqlite"
}

@test "match_render_sqlite: matches a real .db database" {
  match_render_sqlite "$FIX/t.db"
}

@test "match_render_sqlite: declines a non-sqlite extension" {
  ! match_render_sqlite "$FIX/t.txt"
}

# ---- degrade: sqlite3 absent ----

@test "match_render_sqlite: declines when sqlite3 is absent from PATH" {
  export PATH="$ONLYBASE"
  ! command -v sqlite3 >/dev/null 2>&1
  ! match_render_sqlite "$FIX/t.sqlite"
}

@test "render-registry: sqlite3 absent routes a real database to fallback via render_any" {
  export PATH="$ONLYBASE"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.sqlite'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/t.sqlite" ]
}

# ---- negative control: binary garbage renamed .sqlite/.db ----

@test "match_render_sqlite: declines binary garbage renamed .sqlite (keys on type, not extension)" {
  ! match_render_sqlite "$FIX/fake.sqlite"
}

@test "match_render_sqlite: declines binary garbage renamed .db (keys on type, not extension)" {
  ! match_render_sqlite "$FIX/fake.db"
}

@test "render-registry: binary garbage renamed .db routes to fallback, never sqlite3" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.db'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.db" ]
  [ ! -e "$SQLITE3_ARGV_FILE" ]
}

# ---- render: read-only, schema + tables, never a row dump ----

@test "render_sqlite: calls sqlite3 with -readonly on the file" {
  export PATH="$STUB:$PATH"
  run render_sqlite "$FIX/t.sqlite"
  [ "$status" -eq 0 ]
  [ -f "$SQLITE3_ARGV_FILE" ]
  grep -qx -- '-readonly' "$SQLITE3_ARGV_FILE"
  grep -qx -- "$FIX/t.sqlite" "$SQLITE3_ARGV_FILE"
}

@test "render_sqlite: asks for .tables and .schema, never a SELECT" {
  export PATH="$STUB:$PATH"
  run render_sqlite "$FIX/t.sqlite"
  [ "$status" -eq 0 ]
  grep -qx -- '.tables' "$SQLITE3_ARGV_FILE"
  grep -qx -- '.schema' "$SQLITE3_ARGV_FILE"
  ! grep -qi -- 'select' "$SQLITE3_ARGV_FILE"
}

@test "render_sqlite: on a real database shows schema and table list, never row data" {
  run render_sqlite "$FIX/t.sqlite"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CREATE TABLE t"* ]]
  [[ "$output" == *"t"* ]]
  # the actual row values must never appear - this is a schema/tables view.
  [[ "$output" != *"'x'"* ]]
  [[ "$output" != *"'y'"* ]]
}

@test "render_sqlite: a write attempt against the readonly handle fails (SAFETY guarantee, live sqlite3)" {
  run sqlite3 -readonly "$FIX/t.sqlite" "insert into t values (3,'z')"
  [ "$status" -ne 0 ]
  [[ "$output" == *"readonly"* ]]
}
