# shellcheck shell=bash
# vcs.sh: a bare commit SHA -> `git show`, a `#123` ref or a GitHub PR URL ->
# `gh pr view`, render-mode `command`. Untrusted clipboard input reaches an
# external command here, so every accepted shape is validated by an anchored
# regex (^...$, no partial match) and handed to git/gh as ONE argv element in
# a bash array, never rebuilt from a flattened string, never word-split.
# shellcheck disable=SC2034  # RESOLVED_* are consumed by the caller (resolve_any_token's caller)

# A commit SHA is hex-only (0-9a-f), 7-40 chars - never contains a dash, so
# it can never itself be mistaken for a flag.
_VCS_SHA_RE='^[0-9a-f]{7,40}$'
# "#123": a bare PR/issue-style reference. The captured number is digits
# only (see handle_vcs), so it can never start with '-' either.
_VCS_HASHREF_RE='^#[0-9]+$'
# A GitHub PR URL, anchored end-to-end (owner/repo char set matches GitHub's
# own username/repo rules; number is digits only; optional trailing slash).
# Deliberately narrow: this is NOT the general blob/raw shape github.sh
# already owns, and it must not accidentally swallow a blob URL that happens
# to contain "/pull/" as a path segment (blob URLs never have this exact
# .../pull/<digits> tail).
_VCS_PR_URL_RE='^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+/?$'

match_vcs() {
  [ -n "$1" ] || return 1
  [[ "$1" =~ $_VCS_SHA_RE ]] && return 0
  [[ "$1" =~ $_VCS_HASHREF_RE ]] && return 0
  [[ "$1" =~ $_VCS_PR_URL_RE ]] && return 0
  return 1
}

# handle_vcs <raw>: dispatches purely on the token's own prefix, with no
# re-validation - it trusts resolve_any_token already gated the shape via
# match_vcs. Every branch below builds RESOLVED_CMD by quoting "$raw" (or a
# value derived from it) as a single bash-array element, so the argv-safety
# holds independent of the regex above (see tests/handlers-vcs.bats' "argv
# shape control", which calls this function directly, bypassing match_vcs,
# to prove the quoting itself - not the input filter - is what keeps a
# space-containing value as one arg).
handle_vcs() {
  local raw="$1" n
  case "$raw" in
    '#'*)
      n="${raw#\#}"
      RESOLVED_TARGET=""
      RESOLVED_LINE=""
      RESOLVED_MODE="command"
      RESOLVED_CMD=(gh pr view "$n")
      return 0
      ;;
    https://github.com/*)
      # gh pr view accepts a full PR URL directly; no need to pick apart
      # owner/repo/number ourselves.
      RESOLVED_TARGET=""
      RESOLVED_LINE=""
      RESOLVED_MODE="command"
      RESOLVED_CMD=(gh pr view "$raw")
      return 0
      ;;
    *)
      # A commit SHA. `--end-of-options` (not a trailing `--`) is
      # deliberate: `git show -- "$sha"` looks like the obvious
      # flag-injection guard, but git's `--` also means "everything after
      # this is a pathspec, not a revision" - for a SHA that doesn't
      # resolve to a real object, that silently falls back to rendering
      # HEAD's commit (wrong data, not an error) instead of the "not found"
      # degrade this sub-goal's quality bar requires. `--end-of-options`
      # gives the same "this can't be interpreted as a flag" protection
      # without that pathspec reinterpretation - verified against both a
      # real and a bogus-but-hex-shaped SHA (see PR body run-table).
      RESOLVED_TARGET=""
      RESOLVED_LINE=""
      RESOLVED_MODE="command"
      RESOLVED_CMD=(git show --end-of-options "$raw")
      return 0
      ;;
  esac
}
