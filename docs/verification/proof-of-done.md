# Proof of done, SPEC-001 LESSOPEN render dispatch + stacked preview

Lane: full. Branch: `feat/lessopen-render-stack`.

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A markdown preview runs as `less <file>`, filename known | met | `render_any` routes markdown to `render_file_backed`; test "dispatches to the file-backed path" |
| 2 | `o` / `e` / `D` work from a markdown preview | met by construction | `render_file_backed` exports `VISUAL` + `QUICKLOOK_EDITOR_SCRIPT` and execs `less <file>`, the same wiring text.sh used; the %-codes now have a file to expand against |
| 3 | #72 filename regression gone | met | glow no longer feeds less; it is the LESSOPEN preprocessor's stdout and less opens the real `.md` |
| 4 | `,` / Backspace pop, no strand at depth 1 | partially met | keys bound to `remove-file` and the lesskey compiles; `q` deliberately left as close (see deviation) |
| 5 | `q` closes the pane from any depth | met | binding unchanged |
| 6 | Every existing test still passes | met | 511 passed, 0 failed |

## Confirmation runs

| Check | Command | Result |
|---|---|---|
| Full suite | `bats tests/` | **511 passed, 0 failed** |
| Lint | `shellcheck -x scripts/*.sh scripts/renderers/*.sh scripts/handlers/*.sh` | clean |
| lesskey validity | `lesskey -o /dev/null lesskey` | compiles |
| Dispatch routing | `emit_supported` on three files | `CHANGELOG.md` → file-backed; `scripts/lib.sh` (text) → own renderer; `demo/preview.gif` → own renderer |
| emit half is pager-free | `emit_markdown` under stubbed glow/less | emits `GLOW_ARGS:`, never `LESS_ARGS:` |

## The pty probes (design evidence)

`less` semantics were measured, not assumed, with a pty harness
(`scratchpad/pty2.py`, reproduce below). Two controls prove the probe
discriminates.

| Probe | Result |
|-------|--------|
| `:e <file>` pushes onto the file list and jumps to it | true |
| `:d` pops back to the previous file, less survives | true |
| `:d` on the LAST remaining file exits less | **false** |
| control: plain `q` exits | true |
| control: no keypress, still running | true |

## Deviation from the agreed design

The plan was ONE key that pops when the stack is deep and closes at the
bottom. Probe 3 refutes it: `:d` on the last file leaves less running, so
binding `q` to `remove-file` would strand the user on a page they cannot
dismiss. `lesskey` cannot branch and all three shell-out slots (`o`/`e`/`D`)
are taken, so the decision cannot move into shell either.

Shipped instead: `q` keeps its plain meaning (close), and pop gets its own
keys (`,` and Backspace).

## Not covered by this proof

- **The Ctrl+click push is unexercised here.** It needs a human in the
  terminal. The code path is reasoned and lint-clean but has no recorded run.
- `emit_text` is deliberately absent, so text/code previews keep their
  existing renderer; short text files still pipe and are not stack
  participants. Follow-up.
- The remaining pageable kinds (archive, csv, ipynb, json, pdf, plist,
  sqlite) have no `emit_` half yet and keep their current behaviour.

## Reproduce

```sh
cd ~/workspace/tieubao/herdr-quicklook
bats tests/
shellcheck -x scripts/*.sh scripts/renderers/*.sh scripts/handlers/*.sh
lesskey -o /dev/null lesskey
python3 -u <scratchpad>/pty2.py     # less :e / :d semantics, with controls
```
