#!/usr/bin/env bats
# Tests for scripts/install-renderers.sh: dry-run-default (never touches the
# host), --apply's brew calls, tier selection (--p1/--p2/--p3), idempotence
# (a tool already on PATH is skipped), and usage on an unknown flag.
#
# PATH-stub gotcha (see NOTES.md / recents.bats), sharpened for this suite:
# the dev host ships jq AND sqlite3 as base binaries under /usr/bin (not
# just via Homebrew), alongside dirname/grep/etc. So "exclude
# /opt/homebrew/bin" alone is not enough here -- every installer run below
# gets PATH="$STUB:/bin" ONLY (via a scoped assignment on the `run` line,
# never a persistent `export`), where /bin has just enough coreutils (cat,
# bash, chmod, mkdir...) for the script to execute, but no jq/sqlite3/dirname.
# $STUB supplies a `dirname` shim (the script's one real external
# dependency besides an optional `brew`) plus whatever brew/tool stubs a
# given test needs. Because PATH is only ever scoped to the `run` line
# itself, the test body's OWN grep/cat calls keep running under bats' normal
# (unrestricted) PATH.

setup() {
  SCRIPT_SRC="$BATS_TEST_DIRNAME/../scripts/install-renderers.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo/scripts"
  cp "$SCRIPT_SRC" "$FIX/repo/scripts/install-renderers.sh"
  chmod +x "$FIX/repo/scripts/install-renderers.sh"

  STUB="$(mktemp -d)"
  # dirname shim: the only external binary install-renderers.sh calls
  # besides an optional brew (it derives repo_root from dirname
  # "${BASH_SOURCE[0]}"). Real dirname lives in /usr/bin alongside jq/
  # sqlite3 on this host, so it can't be relied on once /usr/bin is
  # excluded; this pure-bash shim covers the one shape the script needs
  # (a plain absolute/relative file path, no trailing slash).
  cat >"$STUB/dirname" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  */*) printf '%s\n' "${1%/*}" ;;
  *) printf '%s\n' "." ;;
esac
EOF
  chmod +x "$STUB/dirname"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

# run_installer <args...>: runs the fixture script with PATH scoped to
# "$STUB:/bin" for this one invocation only (never a persistent export), so
# no real Homebrew-installed or base-system tool on this dev host can leak
# through and no assertion later in the test loses grep/cat.
run_installer() {
  PATH="$STUB:/bin" run bash "$FIX/repo/scripts/install-renderers.sh" "$@"
}

# brew_stub_present: a fake `brew` in $STUB that logs every invocation's
# argv to $FIX/brew.log and no-ops (exit 0). Never a real install.
brew_stub_present() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/brew.log"\nexit 0\n' "$FIX" >"$STUB/brew"
  chmod +x "$STUB/brew"
}

# stub_present_bin <name>: makes <name> resolve on PATH via $STUB, so the
# installer reports it "already installed" without touching a real tool.
stub_present_bin() {
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/$1"
  chmod +x "$STUB/$1"
}

@test "install-renderers.sh: bare invocation previews and exits 0, never calls brew to install" {
  brew_stub_present
  run_installer
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"would install: brew install glow"* ]]
  # brew was never invoked at all (dry-run only detects it via command -v)
  [ ! -e "$FIX/brew.log" ]
}

@test "install-renderers.sh: --dry-run explicitly behaves the same as bare" {
  brew_stub_present
  run_installer --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would install: brew install chafa"* ]]
  [ ! -e "$FIX/brew.log" ]
}

@test "install-renderers.sh: --apply calls the stubbed brew install with the right formulae" {
  brew_stub_present
  run_installer --apply
  [ "$status" -eq 0 ]
  for formula in glow chafa hexyl librsvg poppler qsv jq pandoc ffmpeg sqlite; do
    grep -q "^install $formula\$" "$FIX/brew.log"
  done
}

@test "install-renderers.sh: --p1 only touches the P1 set" {
  brew_stub_present
  run_installer --p1 --apply
  [ "$status" -eq 0 ]
  grep -q "^install glow\$" "$FIX/brew.log"
  grep -q "^install chafa\$" "$FIX/brew.log"
  grep -q "^install hexyl\$" "$FIX/brew.log"
  # none of P2/P3's formulae were installed
  ! grep -q "^install librsvg\$" "$FIX/brew.log"
  ! grep -q "^install poppler\$" "$FIX/brew.log"
  ! grep -q "^install qsv\$" "$FIX/brew.log"
  ! grep -q "^install jq\$" "$FIX/brew.log"
  ! grep -q "^install pandoc\$" "$FIX/brew.log"
  ! grep -q "^install ffmpeg\$" "$FIX/brew.log"
  ! grep -q "^install sqlite\$" "$FIX/brew.log"
}

@test "install-renderers.sh: a tool already on PATH is reported already-installed with no brew call for it" {
  brew_stub_present
  stub_present_bin jq
  run_installer --p2 --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed: jq (jq)"* ]]
  ! grep -q "^install jq\$" "$FIX/brew.log"
  # its P2 siblings still get installed
  grep -q "^install librsvg\$" "$FIX/brew.log"
  grep -q "^install poppler\$" "$FIX/brew.log"
  grep -q "^install qsv\$" "$FIX/brew.log"
}

@test "install-renderers.sh: a multi-binary tool (poppler) needs every binary present to skip" {
  brew_stub_present
  stub_present_bin pdftoppm
  run_installer --p2 --apply
  [ "$status" -eq 0 ]
  # pdftotext is still missing, so poppler is NOT reported already-installed
  grep -q "^install poppler\$" "$FIX/brew.log"
}

@test "install-renderers.sh: no brew on PATH prints the manual fallback as a comment, never fails" {
  run_installer --p1
  [ "$status" -eq 0 ]
  [[ "$output" == *"# no brew found -- install manually: apt install glow"* ]]
}

@test "install-renderers.sh: no brew on PATH with --apply still exits 0 and never installs" {
  run_installer --p1 --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"# no brew found -- install manually"* ]]
  [ ! -e "$FIX/brew.log" ]
}

@test "install-renderers.sh: an unknown flag exits nonzero with usage" {
  brew_stub_present
  run_installer --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}
