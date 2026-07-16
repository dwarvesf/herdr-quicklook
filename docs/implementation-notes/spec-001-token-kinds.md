# Implementation notes: SPEC-001 (token kinds + agent-push + tests)

Deltas from the spec only; the spec records the intended design.

## 2026-07-16 19:55 resolve() now returns absolute paths (not in spec)

Context: TASK-005's suite failed on cases the spec did not predict.
Decision: `resolve`'s as-is branch absolutizes relative hits (`$PWD/` prefix).
Why: a cwd-relative hit returned the path verbatim, which silently broke
open-in-viewer's repo-containment check (`[[ "$target" != "$root"/* ]]`) and
would have mis-labeled in-repo files as "outside this repo". Latent v0.1 bug,
caught by the new tests before any user hit it.
Alternatives: fixing the containment check to handle relative paths; rejected
because every downstream consumer is simpler with one invariant (absolute out).
Impact: none visible to users; CHANGELOG notes the fix.

## 2026-07-16 19:56 test fixtures canonicalize /var vs /private/var

Context: macOS `mktemp -d` returns `/var/...` (a symlink), while git prints
resolved `/private/var/...` paths; string equality in tests failed.
Decision: fixture root is `$(cd "$(mktemp -d)" && pwd -P)`.
Why: normalize once in setup instead of sprinkling `realpath` in assertions.
Impact: tests only.

## 2026-07-16 19:58 incident: mutation control wiped uncommitted work

Context: the spec's negative control (mutate a probe, expect red) was run
BEFORE the first checkpoint commit; the restore step used
`git checkout -- scripts/lib.sh`, which reverted to the last COMMITTED state
(v0.1) and destroyed the uncommitted v0.2 lib.sh additions.
Recovery: re-applied from session context, suite back to 30/30, committed
immediately (`d144893`).
Lesson: checkpoint-commit BEFORE any deliberately destructive verification
step; `git checkout --` is a restore-from-commit, not an undo-last-edit.

## 2026-07-16 20:40 review-team fixes (2 CRITICAL + hardening)

Two fresh-context reviewers (security + correctness) both returned DO NOT SHIP.
Fixes applied on-branch:

- CRITICAL (correctness): `open-preview.sh`'s `set --` clobbered `$1` before the
  arg-forward check, so agent-push lost the token AND every normal invocation
  injected `--env QUICKLOOK_TOKEN=plugin` (argv[0]), breaking the v0.1 clipboard
  flow. Fix: capture `token="${1:-}"` before the first `set --`. Now covered by
  the new `tests/open-preview.bats` (stub-herdr argv capture) so it cannot
  regress unseen again.
- CRITICAL (security): a crafted GitHub URL (`blob/main//etc/passwd`,
  `blob/main/../../etc/passwd`) smuggled an absolute/traversal path through
  `resolve_github` -> `resolve`'s literal `-f` -> rendered in the overlay: a
  local-secret-exfil primitive reachable via the untrusted `QUICKLOOK_TOKEN`
  channel. Fix: `unsafe_relpath` rejects absolute + `..` candidates at the
  source in `resolve_github`. Deliberately NOT adding a repo-root jail to
  `preview-pane.sh` (the reviewer's defense-in-depth suggestion): plain absolute
  paths and `QUICKLOOK_ROOTS` targets outside the repo are INTENDED behavior for
  the `path` class, and a blanket jail would regress them. The smuggle only
  existed for the `github` class, where the path is contractually repo-relative,
  so the source fix fully closes it.
- HIGH: query strings (`?plain=1`) now stripped in `map_github_url` before
  splitting (were causing every such URL to miss locally).
- HIGH/MED: `urldecode` no longer maps `+`->space (wrong for URL paths, broke
  `c++.md`) and escapes backslashes before `printf '%b'` so attacker literal
  `\n`/`\x` cannot smuggle control bytes.
- MED (security): `open-in-viewer.sh` rejects control chars in `$rel` before
  `send-text` (TUI keystroke-injection guard).
- MED (security): `escalate.sh` runs open-in-viewer with `env -u QUICKLOOK_TOKEN`
  so the escalation opens the file the user is actually reading, not a stale
  inherited token.

Coverage grew 30 -> 41 cases (+ 3 in a new script-level file): traversal/absolute
rejection, `/raw/` extraction, query strip, literal-`+`/backslash preservation,
and the open-preview forwarding contract. All PoCs from both reviews re-run and
confirmed blocked (recorded in the proof).

## 2026-07-16 20:05 live agent-push proof runs against a --ref install

Context: the spec's Verification wants a recorded live overlay run; the Air's
plugin registry is down (upstream herdr #893) and the Mini runs the published
v0.1.
Decision: install the feature branch on the Mini via
`herdr plugin install dwarvesf/herdr-quicklook --ref feat/token-kinds --yes`,
then drive `plugin pane open --env QUICKLOOK_TOKEN=...` and `pane read` the
overlay to verify rendered content headlessly.
Why: proves the real end-to-end path (manifest -> pane -> env -> render) on a
real herdr 0.7.4 server without waiting for the Air restart.
Impact: proof recorded in docs/proof-of-done.md; Mini goes back to the
published release after merge.
