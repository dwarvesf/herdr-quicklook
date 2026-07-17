#!/usr/bin/env bash
# release.sh: the ENTIRE release path for herdr-quicklook, run by hand.
#   ./scripts/release.sh X.Y.Z
#
# No CI trigger, no automation watching for a tag push: this script IS the
# trigger. Sanity checks first (clean tree, on main, the tag doesn't already
# exist locally or on origin, shellcheck + bats both green) - nothing is
# mutated until every one of those passes. Then: bump the version in
# herdr-plugin.toml, move CHANGELOG.md's "## Unreleased" section into a
# dated "## X.Y.Z (date)" section (Unreleased itself stays, now empty, at
# the top for the next cycle), commit `chore(release): vX.Y.Z`, tag, push
# commit + tag, and cut a GitHub release with the moved section as the
# notes body.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

die() {
  printf 'release: %s\n' "$1" >&2
  exit 1
}

version="${1:-}"
[ -n "$version" ] || die "usage: $0 X.Y.Z"
# Anchored: a leading 'v', a pre-release/build suffix, or anything non-numeric
# is refused rather than silently mangled into a tag name.
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z (semver, no leading 'v'), got: $version"
tag="v$version"

command -v git >/dev/null 2>&1 || die "git not found"
command -v gh >/dev/null 2>&1 || die "gh not found"
[ -f herdr-plugin.toml ] || die "herdr-plugin.toml not found (run from a repo checkout)"
[ -f CHANGELOG.md ] || die "CHANGELOG.md not found"

# ---- sanity checks: read-only, nothing below this block is mutated until
# every check passes ----

branch="$(git branch --show-current)"
[ "$branch" = "main" ] || die "refusing: on branch '$branch', not main"

[ -z "$(git status --porcelain)" ] || die "refusing: working tree is not clean (commit or stash first)"

# Idempotence guard: a tag that already exists, locally or on origin, means
# this version was released before (or someone beat us to the name).
git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1 &&
  die "refusing: tag $tag already exists locally"
git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1 &&
  die "refusing: tag $tag already exists on origin"

grep -q '^## Unreleased$' CHANGELOG.md ||
  die "CHANGELOG.md has no '## Unreleased' section to release"

echo "release: shellcheck ..."
shellcheck -x scripts/*.sh scripts/handlers/*.sh || die "shellcheck failed"

echo "release: bats tests/ ..."
bats tests/ || die "bats suite failed"

# ---- rewrite CHANGELOG.md: move the Unreleased section's body into a new
# dated section, leaving Unreleased itself empty at the top. Streams the
# file line-by-line rather than slurping it into an awk multi-line variable,
# so this stays a plain, readable bash loop instead of a second scripting
# language embedded in a heredoc. ----

today="$(date +%Y-%m-%d)"
changelog_tmp="$(mktemp)"
notes_file="$(mktemp)"
trap 'rm -f "$changelog_tmp" "$notes_file"' EXIT

render_changelog() {
  local in_unreleased=0 header_done=0 pending_blank=0 line

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$header_done" -eq 0 ] && [ "$line" = "## Unreleased" ]; then
      printf '## Unreleased\n\n## %s (%s)\n' "$version" "$today"
      in_unreleased=1
      header_done=1
      continue
    fi
    if [ "$in_unreleased" -eq 1 ]; then
      if [[ "$line" == "## "* ]]; then
        in_unreleased=0
        printf '\n'
        # fall through: print this next-section header line below
      else
        if [ -z "$line" ]; then
          pending_blank=1
          continue
        fi
        if [ "$pending_blank" -eq 1 ]; then
          printf '\n'
          pending_blank=0
        fi
        printf '%s\n' "$line"
        continue
      fi
    fi
    printf '%s\n' "$line"
  done <CHANGELOG.md
}

render_changelog >"$changelog_tmp"
[ -s "$changelog_tmp" ] || die "changelog rewrite produced an empty file, aborting before overwrite"
grep -q "^## $version (" "$changelog_tmp" ||
  die "changelog rewrite did not produce a '## $version (...)' section, aborting"

# The dated section's own body, trimmed of its trailing blank line, becomes
# the GitHub release notes body.
awk -v hdr="## $version (" '
  index($0, hdr) == 1 { grab = 1; next }
  grab && /^## / { exit }
  grab && !started && $0 == "" { next }
  grab { started = 1; print }
' "$changelog_tmp" >"$notes_file"

mv -f "$changelog_tmp" CHANGELOG.md

# ---- version bump ----

sed -i.bak -E "s/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"/version = \"$version\"/" herdr-plugin.toml
rm -f herdr-plugin.toml.bak
grep -q "^version = \"$version\"\$" herdr-plugin.toml ||
  die "version bump did not take (herdr-plugin.toml has no version = \"$version\" line, aborting before commit)"

# ---- commit, tag, push, release ----

git add herdr-plugin.toml CHANGELOG.md
git commit -m "chore(release): $tag"
git tag "$tag"
git push origin "$branch"
git push origin "$tag"

gh release create "$tag" --title "$tag" --generate-notes --notes-file "$notes_file"

echo "release: $tag shipped"
