# Proof of done, SPEC-001 LESSOPEN render dispatch + stacked preview

Lane: full. Branch: `feat/lessopen-render-stack`. Type: behavioral.

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | A markdown preview runs as `less <file>`, filename known | met |
| 2 | `o` / `e` / `D` work from a markdown preview | met by construction |
| 3 | #72 filename regression gone | met |
| 4 | `,` / Backspace pop, no strand at depth 1 | met (keys bound; `q` unchanged, see deviation) |
| 5 | `q` closes the pane from any depth | met (binding untouched) |
| 6 | Every existing test still passes | met |

## Confirmation run-table

```
Command: bats tests/
Exit:    0
Result:  511 passed, 0 failed
Verdict: PASS

Command: shellcheck -x scripts/*.sh scripts/renderers/*.sh scripts/handlers/*.sh
Exit:    0
Result:  no findings
Verdict: PASS

Command: lesskey -o /dev/null lesskey
Exit:    0
Result:  compiles (deprecation NOTE only)
Verdict: PASS

Command: bash -c '. scripts/lib.sh; emit_supported <path>' for three kinds
Exit:    0
Result:  CHANGELOG.md -> file-backed; scripts/lib.sh (text) -> own renderer;
         demo/preview.gif -> own renderer
Verdict: PASS
```

## Negative control (revert -> RED -> restore)

The claim under test: markdown reaches the file-backed path *because* it
declares an `emit_` half. Break exactly that and the test must go red.

```
Step 1 BASELINE
Command: bats tests/renderers-markdown.bats -f "file-backed path"
Result:  ok 1 render_any: glow present - a .md file dispatches to the file-backed path
Verdict: GREEN

Step 2 BREAK
Command: sed -i '' 's/^emit_markdown() {/emit_markdown_DISABLED() {/' \
           scripts/renderers/markdown.sh
Result:  markdown no longer declares an emit_ half

Step 3 NEGATIVE CONTROL
Command: bats tests/renderers-markdown.bats -f "file-backed path"
Result:  not ok 1 ... `[ "$output" = "FILE-BACKED:$FIX/doc.md" ]' failed
Verdict: RED  <-- the test genuinely detects the mechanism

Step 4 RESTORE
Command: git checkout scripts/renderers/markdown.sh
         bats tests/renderers-markdown.bats
Result:  ok 1 (file-backed path); 25/25 markdown tests pass
Verdict: GREEN
```

## `less` semantics (pty probes, with controls)

Measured with `pty2.py`, not assumed. Two controls prove the probe
discriminates between "exited" and "still running".

| Probe | Result |
|-------|--------|
| `:e <file>` pushes onto the file list and jumps to it | true |
| `:d` pops back to the previous file, less survives | true |
| `:d` on the LAST remaining file exits less | **false** |
| control: plain `q` exits | true |
| control: no keypress, still running | true |

## Deviation from the agreed design

One key that pops when deep and closes at the bottom is **not achievable**.
Probe 3 shows `:d` on the last file leaves less running, so binding `q` to
`remove-file` would strand the user on a page they cannot dismiss. `lesskey`
cannot branch and all three shell-out slots (`o`/`e`/`D`) are taken, so the
decision cannot move into shell. Shipped: `q` = close (unchanged), pop on `,`
and Backspace.

## Gaps, what this proof does NOT cover

- **The Ctrl+click push has no recorded run.** It needs a human in the
  terminal; the transport is the one hint-pane uses in production, and the
  preview opens as an overlay (which `DESIGN.md` says participates in
  Ctrl+click resolution), but this is reasoning, not evidence.
- `emit_text` is absent by choice: text/code previews keep their existing
  renderer and short text files still pipe, so they are not stack
  participants.
- archive, csv, ipynb, json, pdf, plist, sqlite are unconverted.

## Reproduce

```sh
cd ~/workspace/tieubao/herdr-quicklook
bats tests/
shellcheck -x scripts/*.sh scripts/renderers/*.sh scripts/handlers/*.sh
lesskey -o /dev/null lesskey
python3 -u <scratchpad>/pty2.py
```

---

## Addendum — live push/pop run (closes the "no recorded run" gap)

The plugin is linked (`local:~/workspace/tieubao/herdr-quicklook`), so the
branch under test is what herdr actually runs. Push and pop were therefore
exercised against a REAL preview pane over the socket, not reasoned about.
Only the Ctrl+click itself (herdr's link-handler dispatch into `open-link`)
remains unexercised.

```
Command: open preview on CHANGELOG.md, send ":e DESIGN.md" + Enter, send ","
Exit:    0
Result:  base = CHANGELOG (has "Unreleased", lacks "Token flow")
         push = DESIGN    (has "Token flow", lacks "Unreleased")
         pop  = CHANGELOG (has "Unreleased", lacks "Token flow")
Verdict: PASS
```

Each assertion requires the OTHER document's marker to be ABSENT, so a no-op
fails. That mattered: the first version of this run asserted on strings that
also appear in the pager footer, which is baked once at pane start and never
changes, so its pop check would have passed even if nothing had happened. A
second false pass came from a marker (`Handler registry`) that sits below the
first screenful; `pane read --source visible` cannot see it. Both were test
defects, not product defects, but both produced a confident wrong verdict
first.

## Two bugs this run surfaced

1. **Monochrome markdown** (fixed, commit `a2d6510`). Moving the render into
   `render-open.sh` left `CLICOLOR_FORCE=1` behind in
   `render_command_in_pager`. glow is termenv-based and drops to a no-colour
   profile whenever stdout is not a tty, and in the preprocessor its stdout
   is a pipe. Measured on CHANGELOG.md through the real path: **11 coloured
   lines before, 154 after**. Regression test added in
   `tests/render-open.bats`.

2. **The footer does not follow the stack** (OPEN). After pushing to
   DESIGN.md the footer still reads `CHANGELOG.md`, because
   `pager_prompt_args` bakes the static `QUICKLOOK_OBJECT_LABEL` into the
   `less -P` string once at pane start. Not a one-liner: `less -P` offers
   `%f` (full path) but no basename escape, and a full absolute path would
   crowd the key hints off a narrow footer. Deferred, not fixed.
