#!/usr/bin/env bats
# Tests for scripts/renderers/archive.sh (zip/tar/tgz/jar content listings
# via unzip -l / tar -tf, v0.4 SG-06/P2). Same fixture/sourcing shape as
# tests/render-registry.bats.
#
# unzip/tar are base-system on macOS + Linux (never absent in practice, per
# the ROADMAP type->tool map), so a plain PATH narrowed to /usr/bin:/bin
# still finds them - unlike every other kind in this pack. The tool-absent
# degrade test below needs a SYMLINK-ONLY allowlist (mirroring
# tests/renderers-fallback.bats's ONLYBASE idiom) to simulate the genuinely
# rare case.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  echo hi > "$FIX/a.txt"
  (cd "$FIX" && zip -q t.zip a.txt && tar -cf t.tar a.txt && gzip -c t.tar > t.tgz && cp t.zip t.jar)
  # binary garbage wearing each archive extension - the negative control,
  # same shape as render-registry.bats's own blob.bin.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.zip"
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.tar"
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.tgz"
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.jar"

  # NOARCH: symlinks to ONLY file/tr/less/head/od/dirname (dirname is what
  # lib.sh itself needs at source time for LIB_DIR - see its top) - no
  # unzip, no tar. A narrowed /usr/bin:/bin PATH cannot hide these two
  # (they ARE base-system on macOS/Linux), so only an allowlisted PATH lets
  # the "tool somehow absent" degrade be tested for real, per the ROADMAP
  # note above.
  NOARCH="$(mktemp -d)"
  for b in file tr less head od dirname; do
    ln -s "$(command -v "$b")" "$NOARCH/$b"
  done

  STUB="$(mktemp -d)"
  export UNZIP_ARGV_FILE="$FIX/unzip.argv"
  export TAR_ARGV_FILE="$FIX/tar.argv"
}

teardown() {
  cd /
  # Absolute path, not a PATH lookup: the tool-absent test above narrows
  # PATH down to $NOARCH (no /bin) for the rest of this test invocation -
  # same convention as tests/renderers-fallback.bats's ONLYBASE teardown.
  /bin/rm -rf "$FIX" "$STUB" "$NOARCH"
  # Restore a normal PATH so bats-core's OWN post-teardown bookkeeping
  # (which runs after this function, in the same process) can still find
  # its usual coreutils.
  export PATH="/usr/bin:/bin:$PATH"
}

_stub_unzip() {
  cat > "$STUB/unzip" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$UNZIP_ARGV_FILE"
printf 'UNZIP_LISTING\n'
exit 0
SH
  chmod +x "$STUB/unzip"
}

_stub_tar() {
  cat > "$STUB/tar" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TAR_ARGV_FILE"
printf 'TAR_LISTING\n'
exit 0
SH
  chmod +x "$STUB/tar"
}

# ---- match: unzip/tar present (the normal case, base-system) ----

@test "match_render_archive: matches a real .zip" {
  _stub_unzip
  export PATH="$STUB:$PATH"
  match_render_archive "$FIX/t.zip"
}

@test "match_render_archive: matches a real .jar (zip format)" {
  _stub_unzip
  export PATH="$STUB:$PATH"
  match_render_archive "$FIX/t.jar"
}

@test "match_render_archive: matches a real .tar" {
  _stub_tar
  export PATH="$STUB:$PATH"
  match_render_archive "$FIX/t.tar"
}

@test "match_render_archive: matches a real .tgz" {
  _stub_tar
  export PATH="$STUB:$PATH"
  match_render_archive "$FIX/t.tgz"
}

@test "match_render_archive: declines a non-archive extension" {
  _stub_unzip
  _stub_tar
  export PATH="$STUB:$PATH"
  printf 'hello\n' > "$FIX/t.md"
  ! match_render_archive "$FIX/t.md"
}

# ---- degrade: unzip/tar somehow absent (symlink-only allowlist) ----

@test "match_render_archive: declines when unzip/tar are absent (symlink-only allowlist, no /usr/bin or /usr/local/bin)" {
  export PATH="$NOARCH"
  ! command -v unzip >/dev/null 2>&1
  ! command -v tar >/dev/null 2>&1
  ! match_render_archive "$FIX/t.zip"
  ! match_render_archive "$FIX/t.tar"
}

@test "render-registry: unzip/tar absent - a real zip routes to fallback via render_any" {
  export PATH="$NOARCH"
  # Absolute /bin/bash, not a PATH lookup: $NOARCH does not carry bash
  # itself (only the archive-tool allowlist), same reasoning as the
  # teardown fix above.
  run /bin/bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.zip'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/t.zip" ]
}

# ---- negative control: type mismatch, not just extension ----

@test "match_render_archive: declines binary garbage renamed for each extension (keys on type, not extension)" {
  _stub_unzip
  _stub_tar
  export PATH="$STUB:$PATH"
  ! match_render_archive "$FIX/fake.zip"
  ! match_render_archive "$FIX/fake.jar"
  ! match_render_archive "$FIX/fake.tar"
  ! match_render_archive "$FIX/fake.tgz"
}

@test "render-registry: binary garbage renamed .zip routes to fallback, never unzip" {
  _stub_unzip
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.zip'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.zip" ]
  [ ! -e "$UNZIP_ARGV_FILE" ]
}

# ---- render: content listing, paged ----

@test "render_archive: zip/jar page an unzip -l listing" {
  _stub_unzip
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_archive '$FIX/t.zip'"
  [ "$status" -eq 0 ]
  [ -f "$UNZIP_ARGV_FILE" ]
  grep -qx -- '-l' "$UNZIP_ARGV_FILE"
  grep -qx -- "$FIX/t.zip" "$UNZIP_ARGV_FILE"
  [[ "$output" == *"UNZIP_LISTING"* ]]
}

@test "render_archive: tar/tgz page a tar -tf listing" {
  _stub_tar
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_archive '$FIX/t.tgz'"
  [ "$status" -eq 0 ]
  [ -f "$TAR_ARGV_FILE" ]
  grep -qx -- '-tf' "$TAR_ARGV_FILE"
  grep -qx -- "$FIX/t.tgz" "$TAR_ARGV_FILE"
  [[ "$output" == *"TAR_LISTING"* ]]
}

# ---- real tools end-to-end (no stubs): a genuine listing, not a stub echo ----

@test "render_archive: a real .zip lists its member file via the actual unzip binary" {
  run bash -c ". '$LIB'; render_archive '$FIX/t.zip'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.txt"* ]]
}

@test "render_archive: a real .tgz lists its member file via the actual tar binary" {
  run bash -c ". '$LIB'; render_archive '$FIX/t.tgz'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.txt"* ]]
}
