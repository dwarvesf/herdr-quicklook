#!/usr/bin/env bats
# Tests for augment_roots (lib.sh): implicit parent-level workspace roots.
# Side-by-side layouts (ws/<repo>, ws/<org>/<repo>) must resolve cross-repo
# tokens with NO QUICKLOOK_ROOTS configured; the parents of the current repo
# root are appended (default 2 levels, QUICKLOOK_PARENT_SWEEP overrides,
# 0 disables) and every existing roots loop picks them up unchanged.

setup() {
  # herdr_bin binds at source time; point it at a failing binary BEFORE
  # sourcing so the host's real plugin roots never leak into assertions.
  export HERDR_BIN_PATH=/usr/bin/false
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/ws/org/repo" "$FIX/ws/org/sibling/docs"
  git -C "$FIX/ws/org/repo" init -q -b main
  printf 'x\n' > "$FIX/ws/org/sibling/docs/note.md"
  cd "$FIX/ws/org/repo"
  unset QUICKLOOK_ROOTS QUICKLOOK_PARENT_SWEEP
}

teardown() {
  cd /
  rm -rf "$FIX"
}

@test "augment_roots: appends the repo's parent and grandparent (default 2 levels)" {
  augment_roots
  [[ ":$QUICKLOOK_ROOTS:" == *":$FIX/ws/org:"* ]]
  [[ ":$QUICKLOOK_ROOTS:" == *":$FIX/ws:"* ]]
}

@test "augment_roots: QUICKLOOK_PARENT_SWEEP=1 stops at the parent" {
  QUICKLOOK_PARENT_SWEEP=1
  augment_roots
  [[ ":$QUICKLOOK_ROOTS:" == *":$FIX/ws/org:"* ]]
  [[ ":$QUICKLOOK_ROOTS:" != *":$FIX/ws:"* ]]
}

@test "augment_roots: QUICKLOOK_PARENT_SWEEP=0 disables the sweep" {
  QUICKLOOK_PARENT_SWEEP=0
  augment_roots
  [ -z "${QUICKLOOK_ROOTS:-}" ]
}

@test "augment_roots: an already-configured root is not duplicated" {
  QUICKLOOK_ROOTS="$FIX/ws/org"
  augment_roots
  [ "$QUICKLOOK_ROOTS" = "$FIX/ws/org:$FIX/ws" ]
}

@test "augment_roots: an oversized sweep stops at the filesystem root, no empty segments" {
  QUICKLOOK_PARENT_SWEEP=99
  augment_roots
  [ -n "$QUICKLOOK_ROOTS" ]
  [[ "$QUICKLOOK_ROOTS" != *"::"* ]]
  [[ "$QUICKLOOK_ROOTS" != :* ]]
  [[ "$QUICKLOOK_ROOTS" != *: ]]
}

@test "resolve: an org-prefixed cross-repo token resolves with zero config" {
  augment_roots
  run resolve "sibling/docs/note.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIX/ws/org/sibling/docs/note.md" ]
}

@test "resolve: a repo-relative token from a sibling repo resolves via the sweep" {
  augment_roots
  run resolve "docs/note.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIX/ws/org/sibling/docs/note.md" ]
}

@test "negative control: with the sweep disabled, neither token resolves" {
  QUICKLOOK_PARENT_SWEEP=0
  augment_roots
  ! resolve "sibling/docs/note.md"
  ! resolve "docs/note.md"
}

@test "augment_roots: installed herdr plugin roots join the implicit set" {
  STUB="$(mktemp -d)"
  mkdir -p "$STUB/proot/assets"
  printf '{}' > "$STUB/proot/assets/style.json"
  cat > "$STUB/herdr" <<'SH'
#!/usr/bin/env bash
printf '{}'
SH
  cat > "$STUB/jq" <<SH
#!/usr/bin/env bash
printf 'herdr-file-viewer\t%s\n' "$STUB/proot"
SH
  chmod +x "$STUB/herdr" "$STUB/jq"
  herdr_bin="$STUB/herdr"
  export PATH="$STUB:$PATH"
  QUICKLOOK_PARENT_SWEEP=0
  augment_roots
  [[ ":$QUICKLOOK_ROOTS:" == *":$STUB/proot:"* ]]
  # a plugin-relative token (the assets/markdown-style.json case) resolves
  run resolve "assets/style.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$STUB/proot/assets/style.json" ]
}
