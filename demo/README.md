# demo/

GIFs recorded from a real herdr session with [vhs](https://github.com/charmbracelet/vhs),
covering the token-opening flows and, since v0.4, the render registry itself:

| GIF | Shows |
|---|---|
| `hint-flow-tour.gif` | The hero take: `prefix+v` overlays a one-letter hint on every openable token; a letter pick opens `sample.md` (glow) in herdr's 90% popup, a second pick opens `sample.csv` (qsv table, ~40 rows) with `d`/`u` half-page scroll visibly moving it, a third pick UPPERCASES the letter to open `sample.md` again in a full persistent tab pane instead of the popup |
| `tokens-tour.gif` | Every token kind in one pass: a plain path, a GitHub blob URL (opens the local file), a bare commit SHA (`git show`), a `#123` PR reference (`gh pr view`), a directory (`eza --tree`) |
| `recents.gif` | `prefix+shift+v`: fzf-pick an older entry, proving the reopen bumps it back to the front |
| `render-images-tour.gif` | The images story: a png (inline `chafa` ANSI art), a gif (the same `chafa` still-image path - see the landmine below), an svg (`rsvg-convert` -> `chafa`), a pdf (page-1 poster + extracted text) |
| `render-docs-tour.gif` | The documents story: a markdown file (`glow`), a docx (`pandoc` -> `glow`), a Jupyter notebook (`pandoc`'s ipynb reader -> `glow`) |
| `render-data-fallback.gif` | The data + guard story: a csv (`qsv table`), minified json (`jq`), a sqlite schema (table list + DDL, never a row dump), and the NEGATIVE CONTROL: a file no renderer claims, landing on the always-on guard (`file(1)` + a `hexyl` dump + an install hint) |

## Recording

```sh
git clone <this repo> /private/tmp/demo/herdr-quicklook   # NOT /tmp/... (see below)
cd /private/tmp/demo/herdr-quicklook

# the hero take: hint-pick sample.md then sample.csv, records against its
# own /private/tmp/ql-demo-hint fixtures - run the fixtures script first:
./demo/render-anything-fixtures.sh
vhs demo/hint-flow-tour.tape    # writes demo/hint-flow-tour.gif
gifsicle -O3 --colors 256 demo/hint-flow-tour.gif -o /tmp/h.gif && mv -f /tmp/h.gif demo/hint-flow-tour.gif

vhs demo/tokens-tour.tape        # writes demo/tokens-tour.gif
vhs demo/recents.tape            # writes demo/recents.gif

# The three v0.4 render-type tours record against invented fixtures in a
# neutral /private/tmp scratch dir (never inside this checkout), generated
# by a committed prep script - run it once before any of the three tapes:
./demo/render-anything-fixtures.sh
vhs demo/render-images-tour.tape     # writes demo/render-images-tour.gif
vhs demo/render-docs-tour.tape       # writes demo/render-docs-tour.gif
vhs demo/render-data-fallback.tape   # writes demo/render-data-fallback.gif
gifsicle -O3 --colors 256 demo/render-images-tour.gif -o /tmp/i.gif && mv /tmp/i.gif demo/render-images-tour.gif
gifsicle -O3 --colors 256 demo/render-docs-tour.gif -o /tmp/d.gif && mv /tmp/d.gif demo/render-docs-tour.gif
gifsicle -O3 --colors 256 demo/render-data-fallback.gif -o /tmp/f.gif && mv /tmp/f.gif demo/render-data-fallback.gif
```

`Output` paths in a `.tape` are relative to wherever `vhs` itself is invoked from, not
the tape file's own directory - always `cd` into the checkout first.

## Landmines hit recording these (read before re-recording)

- **`/tmp/...` vs `/private/tmp/...`**: macOS's `/tmp` is a symlink to `/private/tmp`.
  `git rev-parse --show-toplevel` always returns the resolved `/private/tmp/...` form;
  a shell whose `$PWD` shows the symlinked `/tmp/...` form fails `open-in-viewer.sh`'s
  repo-containment check (`target != root/*`) even for a file genuinely inside the repo,
  degrading `o` to "outside this repo's tree". Always `cd` into the real,
  symlink-resolved path.
- **A fresh `--session <name>` starts with an EMPTY plugin registry.** Session-scoped,
  not shared with `default` or with each other: `herdr plugin action list` returns
  `"actions":[]` until you `herdr plugin link <path>` inside that specific session (once
  per plugin, every take). Every tape's hidden setup does this immediately after
  attaching, redirected to `/dev/null` so the link command's own JSON reply never
  pollutes the recording.
- **Env vars exported interactively do NOT reach the overlay pane's process.** The pane
  is spawned by the herdr SERVER, not by the interactive pane's own shell, so
  `export EDITOR=vim` typed at the prompt has zero effect on what `e` invokes (it silently
  fell back to the plugin's `zed --wait` default and popped a REAL GUI Zed window during
  recording - closed immediately, but a genuine hazard worth flagging). Fix: put
  `LANG=... EDITOR=vim` on the SAME line as the `herdr --session` launch itself, so the
  SERVER process inherits them, and every pane it spawns inherits them in turn. Same
  reasoning applies to `LANG`/`LC_ALL` (needed for `eza --tree`'s box-drawing glyphs to
  render instead of raw UTF-8 byte escapes).
- **Re-pressing `prefix+v` a second time in one vhs-driven session did not reliably
  reopen the preview overlay** - confirmed the identical keystroke delivered correctly
  every time via `herdr pane send-keys <pane> v` over the socket API, so this is a
  vhs/pty keystroke-routing quirk specific to the Ctrl+B prefix dispatch, not a product
  bug. Every take past the first `prefix+v` open instead runs
  `herdr plugin action invoke preview --plugin herdr-quicklook >/dev/null 2>&1` directly
  - the exact same entrypoint the keybinding itself runs, so nothing shown is faked.
- **`o` (escalate) pauses on a `less` safety prompt** - "This file was viewed via
  LESSOPEN (press RETURN)" - whenever `bat` is installed (it colorizes the overlay via
  `LESSOPEN`, and `less` warns before handing off to `visual` on a piped source). This is
  real, everyday behavior, not a recording artifact; the tape presses Enter to dismiss it
  like a real user would.
- **`gh pr view` needs a real GitHub remote.** A scratch clone made from a local path
  (`git clone /path/to/worktree ...`) inherits a local-path `origin`, which `gh` can't
  resolve to a repo; `git remote set-url origin git@github.com:dwarvesf/herdr-quicklook.git`
  before recording `tokens-tour.tape`'s PR-reference segment.
- Stray herdr sessions accumulate on the server across recording attempts (harmless but
  should be cleaned up): `herdr session list` then `herdr session stop <name>` for any
  `demo-*`/`clip-*` session left `running`.
- **`git log` (no flags) opens a real `less` pager and eats every keystroke typed
  after it** - a tape that types `ls` and a URL command
  right after populating the busy screen; without `--no-pager`, those characters get
  interpreted as `less` navigation/search keys instead of shell input (confirmed:
  typing `ls` inside `less` opened its help screen). Always `git --no-pager log ...`
  in a tape, never bare `git log`.
- **`herdr plugin pane open`'s own JSON acknowledgment pollutes the recording unless
  redirected.** `scripts/open-popup.sh`, run directly (not through `herdr plugin
  action invoke`), execs `herdr plugin pane open ...` with no output redirection of
  its own - its RPC reply (a `plugin_pane_opened` JSON blob) prints straight into the
  INVOKING pane, not the new popup. The three render-tour tapes drive every open
  through a tiny generated `open` wrapper (`render-anything-fixtures.sh`) that adds
  `>/dev/null 2>&1`, same convention as the existing tapes' `>/dev/null 2>&1` on
  `herdr plugin action invoke preview`.
- **A bare relative filename is one accidental `cd` away from resolving against the
  wrong directory when the render is driven by directly running `open-popup.sh`
  outside herdr's own dispatch.** `open-popup.sh` takes its token as `$1` and
  forwards `QUICKLOOK_PREVIEW_CWD` (env, or `$PWD` as a default) to the popup pane;
  `preview-pane.sh` then `cd`s there before resolving - a plain shell invocation's
  `$PWD` is wherever the wrapper happened to be run from, not necessarily the
  fixture dir. Fix: the `open` wrapper resolves each fixture to an ABSOLUTE path
  (`"$dir/$1"`) AND sets `QUICKLOOK_PREVIEW_CWD="$dir"` explicitly before handing it
  to `open-popup.sh`, sidestepping the cwd question entirely - same precedent as
  `hint.sh`/`hint-pane.sh`'s own `QUICKLOOK_PREVIEW_CWD="$PWD" exec bash
  open-popup.sh` calls.
- **chafa 1.18.2's `--animate` flag requires `--animate=BOOL`, not a bare flag.**
  `scripts/renderers/gif.sh`'s shipped invocation, `chafa --animate -d N -- <path>`,
  mis-parses `-d` as `--animate`'s value on this chafa version (`chafa: Animate mode
  must be one of [on, off]`, exit 2) and falls through to its own fallback, `chafa
  --format symbols -- <path>` - with NO `--animate`/`-d` at all. On a genuinely
  multi-frame gif, chafa defaults `--animate` to on and an unset `--duration` to
  INFINITE for an animation, so that fallback call free-runs forever in a real TTY
  (confirmed live over the herdr socket API - the overlay pane stayed open
  unbounded, `ps` showed no dead process, only cursor-blink-level diffs between
  polls; bare `q` and Ctrl+C delivered to the pane did nothing, since chafa itself
  never reads stdin mid-render). Fixed in #35
  (`--animate=on` + a wall-clock duration bound), so `sample.gif` is a real
  multi-frame animation again.
- **`render-images-tour.gif` re-recorded through the popup surface, verified**:
  the fixture `open` wrapper now execs `scripts/open-popup.sh` (was
  `open-preview.sh`), so every beat below opens in herdr's bordered "Preview"
  popup - visibly inset from the pane, not a full-pane overlay - same surface
  as the hero `hint-flow-tour.gif`. One-dark theme throughout. Raw frame
  indices are against the COMMITTED, `gifsicle -O3 --colors 256`-optimized
  gif (221 frames, variable per-frame delay, 34.68s total) - `gifsicle`
  dedups/merges frames during that optimization pass, so these indices do
  NOT line up with fps math or with the pre-optimization recording; they
  were located by cumulative per-frame delay against each beat's known
  open+hold timing. Frame 56 (t=7.52s): the png (mandelbrot) as inline
  `chafa` ANSI art, inside the popup. Frame 109 (t=16.08s): the gif beat
  mid-animation, same popup, same chafa path (see the chafa landmine below).
  Frame 162 (t=24.44s): the svg's three solid shapes (blue square, red
  circle, green triangle) via `rsvg-convert` -> `chafa`, in the popup. Frame
  217 (t=33.28s): the pdf's page-1 poster (the same mandelbrot image,
  `sips`-converted), in the popup, closing cleanly on `q`. No internal paths
  beyond the scratch dir's own `/private/tmp/ql-demo-images/sample.*` names;
  no client/Dwarves data.
- **`render-docs-tour.gif` re-recorded through the popup surface, verified**:
  same `open` -> `open-popup.sh` wrapper change. One-dark theme throughout.
  Raw frame indices are against the committed, optimized gif (224 frames,
  variable delay, 30.76s total), same dedup caveat as above. Frame 75
  (t=9.44s): the markdown popup shows `# Fruit Stand Notes` (heading, bullet
  list, fenced code block). Frame 146 (t=19.44s): the docx popup renders
  byte-identical prose via `pandoc` -> `glow` (same popup surface, proving
  the conversion round-trips). Frame 219 (t=29.04s): the ipynb popup renders
  its markdown cell (`# Fruit Counter`) + code cell via `pandoc`'s ipynb
  reader -> `glow`. No internal paths beyond `/private/tmp/ql-demo-docs/sample.*`;
  no client/Dwarves data.
- **`render-data-fallback.gif` re-recorded through the popup surface,
  verified**: same `open` -> `open-popup.sh` wrapper change. One-dark theme
  throughout. Raw frame indices are against the committed, optimized gif
  (252 frames, variable delay, 36.88s total), same dedup caveat as above.
  Frame 66 (t=8.04s): the csv popup shows the aligned `qsv table`
  (fruit/qty/price_usd rows). Frame 119 (t=16.52s): the json popup shows the
  pretty-printed `jq .` output (`fruit_stand` object, nested items). Frame
  181 (t=25.6s): the sqlite popup shows the table list (`orders`, `users`) +
  `CREATE TABLE` schema, never a row dump. Frame 246 (t=34.2s): the
  negative-control beat (`mystery.ipynb`, the first 800 bytes of `/bin/ls`,
  real Mach-O binary data wearing a `.ipynb` extension) shows the always-on
  guard inside the SAME popup surface
  - `file(1)`'s real type description, a colorized `hexyl` hexdump, and the
  install hint `install jupyter/nbconvert for a richer preview of .ipynb
  files` - proving the fallback guard lands in the popup too, not a
  different surface. No internal paths beyond `/private/tmp/ql-demo-data/*`;
  every fixture is invented placeholder content (fruit names); no
  client/Dwarves data.
- **Hint-key assignment shifts with whatever is ON SCREEN, including the invoking
  command itself.** `hint`'s ranking is tier-then-bottom-of-screen-first over
  `asdfghjklwertyuiopzxcvbnm`; typing `herdr plugin action invoke hint --plugin
  herdr-quicklook >/dev/null 2>&1` directly into the pane (the CLI-invoke
  precedent, same as every tape past the first `prefix+v`) leaves `/dev/null`
  visible on screen as a real path-tier token, and its line sits BELOW the
  fixture prose - so it claims key `a`, bumping `sample.csv` to `s` and
  `sample.md` to `d` (confirmed empirically: an isolated `herdr pane read` probe
  with the same invoke issued over the API instead, where the command text
  never appears on screen, assigned `a`/`s` to csv/md - the visible redirect
  target is what shifts the map, not the fixtures). Verify the live overlay
  frame before hard-coding a hint letter in a tape; don't assume it from an
  API-only probe.
- **`hint-flow-tour.gif` verified (v2, adds the UPPERCASE tab-pane beat)**:
  one-dark theme throughout. Raw frame indices are against the committed,
  `gifsicle -O3 --colors 256`-optimized gif (341 frames, variable per-frame
  delay via PIL, 39.8s total) - located by cumulative per-frame delay, same
  dedup caveat as the render-*-tour gifs below (gifsicle merges frames during
  optimization, so indices do not line up with fps math). Frame 95 (t=8.32s)
  and frame 269 (t=25.36-30.36s, a single 5s-held frame): the dimmed overlay
  with hints on `notes.txt` (`r`), `sample.md` (`d`), `sample.csv` (`s`), and
  `/dev/null` (`a`) - read live before trusting the letter (see the landmine
  below); it is the SAME map at the first invoke and the third, so `sample.md`
  stayed `d`/`D` throughout this recording. Frame 100 (t=9.56-10.16s): `d`
  picked -> the 90% "Preview" popup renders `sample.md` via glow (bordered,
  inset from the pane) - unchanged from the original beat. Frame 187
  (t=19.16-19.72s): `s` picked -> the qsv table for `sample.csv`
  (`apple-01`...`jackfruit-29`, pre-scroll) - the `d`/`u` half-page scroll
  beat survived re-recording. Frame 280 (t=35.04-35.64s, inside a ~6.3s span
  of near-static frames from a blinking cursor): the THIRD pick, `D`
  (uppercase), opens `sample.md` in a full persistent tab pane - a second tab
  ("2") with NO popup border/inset, visibly distinct from frame 100's bordered
  popup. Frame 284 (t=36.64s): `q` closes the tab cleanly, back to tab "1" -
  no lingering empty tab. Frame 341 (t=39.76s, final frame): the end banner
  (`o = file-viewer · e = editor · D = diff`) renders in the original pane,
  proving focus returned correctly after the tab closed. No internal path
  beyond the workspace label `ql-demo-hint` (the fixture dir's own basename);
  no client/Dwarves data.
