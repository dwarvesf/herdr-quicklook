#!/usr/bin/env bats
# Tests for scripts/release.sh: argv parsing and the refusal guards (dirty
# tree, wrong branch, an already-existing tag), plus the happy path's argv
# shape (right version bump, right tag name, right git/gh calls). git and gh
# are stubbed for every case here, so nothing pushes anywhere real; the
# refusal tests additionally never reach the git-mutating half of the script
# at all (they die() before it).

setup() {
  SCRIPT_SRC="$BATS_TEST_DIRNAME/../scripts/release.sh"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo/scripts/handlers" "$FIX/repo/tests"
  cp "$SCRIPT_SRC" "$FIX/repo/scripts/release.sh"
  chmod +x "$FIX/repo/scripts/release.sh"

  cat >"$FIX/repo/herdr-plugin.toml" <<'EOF'
id = "herdr-quicklook"
name = "herdr-quicklook"
version = "0.1.0"
EOF

  cat >"$FIX/repo/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

- feature one (#1)
- feature two (#2)

## 0.1.0 (2026-07-16)

Initial release.

- initial thing
EOF

  git -C "$FIX/repo" init -q -b main
  git -C "$FIX/repo" add -A
  git -C "$FIX/repo" -c user.email=t@t -c user.name=t commit -qm init

  # Stubs: shellcheck/bats always pass (the sanity-check gate is not what
  # this suite is testing), git/gh log every invocation to $FIX/git.log /
  # $FIX/gh.log and otherwise no-op, so the happy-path test never touches a
  # real remote or GitHub. shellcheck itself lints THIS script elsewhere.
  STUB="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/shellcheck"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB/bats"
  chmod +x "$STUB/shellcheck" "$STUB/bats"

  cd "$FIX/repo"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

# real_git_path: the refusal tests want REAL git semantics (an actual dirty
# tree, an actual existing tag) rather than a canned stub answer, and they
# never reach a mutating git call (the script dies() first), so real git is
# safe here, no network, no push.
real_git_path() {
  export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
}

# stubbed_git_gh_path: for the happy-path test, git AND gh are both fully
# fake, logging their argv to $FIX/git.log / $FIX/gh.log and no-oping.
# Proves release.sh's OWN argv construction (tag name, commit message, gh
# release call) without ever shelling out to real git or gh.
stubbed_git_gh_path() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/git.log"\ncase "$1 $2" in\n  "branch --show-current") echo main ;;\n  "status --porcelain") : ;;\n  "rev-parse -q") exit 1 ;;\n  "ls-remote --exit-code") exit 1 ;;\nesac\nexit 0\n' "$FIX" >"$STUB/git"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/gh.log"\nexit 0\n' "$FIX" >"$STUB/gh"
  chmod +x "$STUB/git" "$STUB/gh"
  export PATH="$STUB:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
}

@test "release.sh: no version argument -> usage error" {
  real_git_path
  run bash scripts/release.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "release.sh: a non-semver argument is refused" {
  real_git_path
  run bash scripts/release.sh v0.3.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must be X.Y.Z"* ]]
}

@test "release.sh: refuses a dirty working tree" {
  real_git_path
  echo "uncommitted" >>README-scratch.md
  run bash scripts/release.sh 0.3.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"working tree is not clean"* ]]
  # never reached the mutating half
  [ "$(git tag -l)" = "" ]
}

@test "release.sh: refuses when not on branch main" {
  real_git_path
  git checkout -qb feat/other
  run bash scripts/release.sh 0.3.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"not main"* ]]
}

@test "release.sh: refuses when the tag already exists locally" {
  real_git_path
  git tag v0.3.0
  run bash scripts/release.sh 0.3.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists locally"* ]]
  # herdr-plugin.toml was never touched
  grep -q 'version = "0.1.0"' herdr-plugin.toml
}

@test "release.sh: happy path builds the right tag name and argv" {
  stubbed_git_gh_path
  run bash scripts/release.sh 1.2.3
  [ "$status" -eq 0 ]

  # version bump landed
  grep -q 'version = "1.2.3"' herdr-plugin.toml

  # CHANGELOG moved Unreleased's body into a dated 1.2.3 section, Unreleased
  # itself left empty at the top
  grep -q '^## Unreleased$' CHANGELOG.md
  grep -q '^## 1.2.3 (' CHANGELOG.md
  ! awk '/^## Unreleased$/{f=1;next} /^## /{f=0} f && NF' CHANGELOG.md | grep -q .

  # right tag, built as v<version> not <version>
  grep -q '^tag v1.2.3$' "$FIX/git.log"
  grep -q '^push origin v1.2.3$' "$FIX/git.log"
  grep -q '^commit -m chore(release): v1.2.3$' "$FIX/git.log"

  # gh release create was called for the same tag, notes-file, not raw --notes
  grep -q 'release create v1.2.3' "$FIX/gh.log"
  grep -q -- '--notes-file' "$FIX/gh.log"
}

@test "release.sh: happy path never calls a bare 'git push origin main' before the tag exists" {
  # Regression guard for push ordering: the commit must be pushed, then the
  # tag, in that order, both to origin - never the tag before the commit
  # that introduces it.
  stubbed_git_gh_path
  run bash scripts/release.sh 4.5.6
  [ "$status" -eq 0 ]
  push_lines="$(grep -n '^push origin' "$FIX/git.log")"
  first_line="$(printf '%s\n' "$push_lines" | head -1)"
  second_line="$(printf '%s\n' "$push_lines" | tail -1)"
  [[ "$first_line" == *"origin main"* ]]
  [[ "$second_line" == *"origin v4.5.6"* ]]
}
