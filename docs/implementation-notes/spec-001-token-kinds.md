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
