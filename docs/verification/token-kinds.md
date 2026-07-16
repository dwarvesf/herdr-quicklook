# Proof of done: SPEC-001 token kinds + agent-push + bats suite

## Acceptance criteria (from SPEC-001)

- Blob/raw GitHub URLs open the local checkout at the line when resolvable,
  browser otherwise.
- Token priority env > arg > clipboard in both actions; preview forwards an
  argument via `--env`.
- `bats tests/` green, covering resolve/parse/classify/priority; v0.1
  clipboard flow regression-checked.

## Confirmation runs

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `shellcheck -x scripts/*.sh` | 0 | PASS |
| 2 | `bats tests/` (30 cases) | 0, `30 ok` | PASS |
| 3 | Negative control: mutate worktree probe (`$w/$p` -> `$w/$p.mutated`), `bats tests/` | non-zero, `not ok 23 resolve: cross-worktree finds worktree-only file` | RED as expected |
| 4 | Restore mutation, `bats tests/` | 0, `30 ok` | PASS (restored) |
| 5 | Live agent-push overlay on the Mini (herdr 0.7.4): `herdr plugin pane open --plugin herdr-quicklook --entrypoint preview --placement overlay --env QUICKLOOK_TOKEN=... --cwd ...` then `herdr pane read` | recorded below | see Run detail |

## Run detail

Runs 1-4 executed locally on the Air, 2026-07-16, branch `feat/token-kinds`.
Run 3+4 is the required negative control: the suite goes red when the
cross-worktree probe is broken and green again on restore, proving the tests
bind to the behavior (run 3 also destroyed uncommitted work via
`git checkout --`; see implementation-notes for the incident and the
checkpoint-first lesson).

Run 5 (live end-to-end): appended after the branch install on the Mini; the
overlay pane's `pane read` output must show the target file's rendered
content, proving manifest -> pane -> `--env` token -> resolve -> render on a
real server with no clipboard involvement.

### Run 5 output

(pending; appended before merge)

## Reproduce

```sh
git switch feat/token-kinds
shellcheck -x scripts/*.sh && bats tests/
# live: on a herdr host with the branch installed
herdr plugin pane open --plugin herdr-quicklook --entrypoint preview \
  --placement overlay --env QUICKLOOK_TOKEN="<repo-relative path>:<line>" --cwd <repo>
herdr pane list   # find the Preview pane id
herdr pane read <pane_id> --lines 20
```
