# demo/

GIFs recorded from a real herdr session with [vhs](https://github.com/charmbracelet/vhs),
covering the token-opening flows and, since v0.4, the render registry itself:

| GIF | Shows |
|---|---|
| `hint-flow-tour.gif` | The hero take: `prefix+v` overlays a one-letter hint on every openable token; a letter pick opens `sample.md` (glow) in herdr's 90% popup, a second pick opens `sample.csv` (qsv table, ~40 rows) with `d`/`u` half-page scroll visibly moving it |
| `linkify.gif` | `prefix+shift+l` opens the link overlay over real pane output; an SGR Ctrl+click opens a bare path locally, closing the preview returns to the link list, and a second Ctrl+click routes the original GitHub blob URL into the local checkout |
| `tokens-tour.gif` | Every token kind in one pass: a plain path, a GitHub blob URL (opens the local file), a bare commit SHA (`git show`), a `#123` PR reference (`gh pr view`), a directory (`eza --tree`) |
| `overlay-keys-tour.gif` | The three in-overlay keys: `d` (dirty-diff toggle), `e` (edit in `$EDITOR`), `o` (escalate to herdr-file-viewer) |
| `recents.gif` | `prefix+shift+v`: fzf-pick an older entry, proving the reopen bumps it back to the front |
| `pluck-full-flow.gif` | The one-key pluck chain: herdr-pluck's hint overlay pops, pick a token, quick-look opens it immediately, no extra keypress |
| `pick-anywhere.gif` | `prefix+v` on a busy pane (real commits, `ls`, a URL): `pluck-chain` reroutes into the native `pick` overlay (herdr-pluck not linked), the count header (`N on screen · A path · B url · ...`) is visible, a pick opens in the preview overlay. Plus the negative control: an empty pane and an empty clipboard yield the honest `quicklook: nothing openable on screen` instead of a crash or silent no-op |
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

vhs demo/linkify.tape           # writes demo/linkify.gif
gifsicle -O3 --colors 256 demo/linkify.gif -o demo/linkify.optimized.gif && mv demo/linkify.optimized.gif demo/linkify.gif
vhs demo/tokens-tour.tape        # writes demo/tokens-tour.gif
vhs demo/recents.tape            # writes demo/recents.gif
vhs demo/pluck-full-flow.tape    # writes demo/pluck-full-flow.gif (needs herdr-pluck)

# overlay-keys-tour.gif is built from three short takes concatenated with
# gifsicle (chaining d -> e -> o in one continuous take was empirically
# unreliable through vhs's synthetic pty, see below):
vhs demo/overlay-keys-d.tape     # writes demo/clip-d.gif
vhs demo/overlay-keys-e.tape     # writes demo/clip-e.gif (needs herdr-file-viewer)
vhs demo/overlay-keys-o.tape     # writes demo/clip-o.gif (needs herdr-file-viewer)
gifsicle --colors 256 demo/clip-d.gif demo/clip-e.gif demo/clip-o.gif > demo/overlay-keys-tour.gif

# pick-anywhere.gif is two short takes (the main flow, then the negative
# control) concatenated with gifsicle, same reason as overlay-keys-tour.gif:
vhs demo/pick-anywhere-main.tape   # writes demo/pick-anywhere-main.gif
vhs demo/pick-anywhere-empty.tape  # writes demo/pick-anywhere-empty.gif
gifsicle --colors 256 demo/pick-anywhere-main.gif demo/pick-anywhere-empty.gif > demo/pick-anywhere.gif

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
- **VHS has no mouse command.** `linkify.tape` composes each real Ctrl+left-click
  as SGR-1006 bytes: `Ctrl+[` emits ESC, then a 1ms `Type` emits the mouse body
  with Ctrl's modifier bit set. The coordinates are pinned to that tape's
  1400x800 / 15px grid; changing its dimensions or moving the demo rows requires
  recapturing the grid and updating the two coordinates. The exact sequences were
  first driven against the same TUI through localterm's PTY API and verified to
  open the intended OSC-8 and direct URL cells before recording.
- **`linkify.tape` creates an isolated native keybinding.** Its hidden setup starts
  from `herdr --default-config`, appends only `prefix+shift+l` as a
  `plugin_action`, and launches a fresh named session with that temp config. It
  never reads or mutates the recorder's normal herdr config.
- **Re-pressing `prefix+v` a second time in one vhs-driven session did not reliably
  reopen the preview overlay** - confirmed the identical keystroke delivered correctly
  every time via `herdr pane send-keys <pane> v` over the socket API, so this is a
  vhs/pty keystroke-routing quirk specific to the Ctrl+B prefix dispatch, not a product
  bug. Every take past the first `prefix+v` open instead runs
  `herdr plugin action invoke preview --plugin herdr-quicklook >/dev/null 2>&1` directly
  - the exact same entrypoint the keybinding itself runs, so nothing shown is faked.
- **Chaining `d` -> `d` -> `e` -> `o` inside one continuous overlay session was flaky**
  even with the CLI-invoke open and generous sleeps (the same keys delivered instantly
  and correctly via `herdr pane send-keys` in isolation). `overlay-keys-tour.gif` is
  therefore three independent short takes (fresh session each), concatenated after the
  fact - each take on its own was reliable on the first or second try.
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
  after it** - `pick-anywhere-main.tape` types `ls` and a `printf ... | ` URL command
  right after populating the busy screen; without `--no-pager`, those characters get
  interpreted as `less` navigation/search keys instead of shell input (confirmed:
  typing `ls` inside `less` opened its help screen). Always `git --no-pager log ...`
  in a tape, never bare `git log`.
- **`pick-anywhere.gif`'s reroute is the REAL production fallback, not a synthetic
  shortcut**: Han's shipped `config.toml` binds `prefix+v` to `pluck-chain`. Neither
  take links `herdr-pluck` into its fresh session, so `pluck-chain`'s own
  soft-dependency check fires for real and reroutes into the native `pick` action -
  the exact path a user with only herdr-quicklook installed hits every time. The
  toast ("herdr-pluck failed to open; opening the pick-anywhere overlay") is real
  herdr notification output, not staged text.
- **`linkify.gif` verified**: one-dark theme; exactly three real candidates;
  underlined OSC-8 labels; the bare `scripts/linkify-pane.sh:30` Ctrl+click opens
  at the target line; `q` returns to the same link overlay; the original GitHub
  blob URL Ctrl+click opens local `scripts/lib.sh` at `#L225`. No internal path
  beyond `/private/tmp/demo-linkify/herdr-quicklook`; no username or client data.
- **`pick-anywhere.gif` verified**: one-dark theme (both takes), main take shows a genuinely busy pane
  (3 real commit SHAs via `git --no-pager log`, real repo file/dir names via `ls`, a
  real URL); this take's count header renders `18 on screen · 8 path · 1 url · 3
  sha · 3 dir · 3 name` (what THIS specific recording's busy pane produced, not a
  general capacity figure - `pick` has no cap), and a real pick (`LICENSE`) opens
  in the preview overlay; negative control shows the honest `quicklook: nothing
  openable on screen` on a cleared pane with an empty clipboard. No internal paths
  beyond the scratch clone's own `/private/tmp/demo/...` directory name; no
  client/Dwarves data.
- **`herdr plugin pane open`'s own JSON acknowledgment pollutes the recording unless
  redirected.** `scripts/open-preview.sh`, run directly (not through `herdr plugin
  action invoke`), execs `herdr plugin pane open ...` with no output redirection of
  its own - its RPC reply (a `plugin_pane_opened` JSON blob) prints straight into the
  INVOKING pane, not the new overlay. The three render-tour tapes drive every open
  through a tiny generated `open` wrapper (`render-anything-fixtures.sh`) that adds
  `>/dev/null 2>&1`, same convention as the existing tapes' `>/dev/null 2>&1` on
  `herdr plugin action invoke preview`.
- **A bare relative filename does not resolve inside the overlay when the render is
  driven by directly running `open-preview.sh`.** `open-preview.sh` derives the
  overlay's cwd from `$HERDR_PLUGIN_CONTEXT_JSON`, which herdr populates only when
  IT dispatches an action (a real keybinding, or `herdr plugin action invoke`) - a
  plain shell invocation of the script never gets that context, so `resolve()`'s
  first check (`[ -f "$p" ]`, cwd-relative) misses and the overlay reports
  `quicklook: not a file I can find`. Fix: the same `open` wrapper resolves each
  fixture to an ABSOLUTE path (`"$dir/$1"`) before handing it to
  `open-preview.sh`, sidestepping the cwd question entirely.
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
  never reads stdin mid-render). `render-anything-fixtures.sh`'s `sample.gif` is
  therefore a SINGLE-FRAME gif - the same `render_gif` code path, but nothing to
  loop, so it closes on the normal "press any key" prompt like every other still
  render. This is a real renderer-side finding worth a follow-up goal (out of scope
  for the docs/demo sub-goal that found it).
- **`render-images-tour.gif` verified**: one-dark theme throughout; png renders as
  inline `chafa` ANSI art (a halftone-like render of the linkify.gif first frame,
  matching its screenshot-of-text content); the gif beat renders the same still-image
  path (see the chafa landmine above) with no error text; the svg renders as three
  solid-color shapes (blue square, red circle, green triangle) via `rsvg-convert` ->
  `chafa`; the pdf beat shows the page-1 poster then the extracted text, both
  cleanly closing. No internal paths beyond the scratch dir's own
  `/private/tmp/ql-demo-images/sample.*` names; no client/Dwarves data.
- **`render-docs-tour.gif` verified**: one-dark theme throughout; the markdown
  renders via `glow` (heading, bullet list, fenced code block all visible); the
  docx renders the SAME content via `pandoc` -> `glow` (byte-identical prose,
  proving the conversion round-trips); the ipynb renders its markdown cell + code
  cell via `pandoc`'s ipynb reader -> `glow`. No internal paths beyond
  `/private/tmp/ql-demo-docs/sample.*`; no client/Dwarves data.
- **`render-data-fallback.gif` verified**: one-dark theme throughout; the csv
  renders as an aligned `qsv table`; the json renders pretty-printed via `jq .`;
  the sqlite beat shows the table list (`users`, `orders`) + `CREATE TABLE`
  schema, never a row dump; the negative-control beat (`mystery.ipynb`, the first
  800 bytes of `/bin/ls`, real Mach-O binary data wearing a `.ipynb` extension)
  shows `file(1)`'s real type description, a colorized `hexyl` hexdump, and the
  install hint `install jupyter/nbconvert for a richer preview of .ipynb files` -
  the always-on guard catching a file no renderer will touch. No internal paths
  beyond `/private/tmp/ql-demo-data/*`; every fixture is invented placeholder
  content (fruit names); no client/Dwarves data.
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
- **`hint-flow-tour.gif` verified**: one-dark theme throughout; frame indices
  from a 5fps extraction of the optimized gif (148 frames, 29.56s). Frame 40
  (t=7.8s) and frame 48 (t=9.4s): the dimmed snapshot with bright-yellow hint
  keys on `notes.txt` (`f`), `sample.md` (`d`), `sample.csv` (`s`), and
  `/dev/null` (`a`). Frame 56/62 (t=11.0-12.2s): `d` picked -> the 90% popup
  renders `sample.md` via glow (`# Fruit Stand Setup` heading, bullet list,
  ordered steps, all visible). Frame 96/100 (t=19.0-19.8s): the SECOND overlay
  invoke shows the identical dim+hint frame with the "pick by letter" banner
  in scrollback above it. Frame 112/118 (t=22.2-23.4s): `s` picked -> the qsv
  table for `sample.csv`, aligned columns, rows `apple-01`...`jackfruit-29`
  visible (pre-scroll). Frame 124 (t=24.6s): after `d`, the table scrolled to
  its last page (`rambutan-30`...`rambutan-40`, `(END)` marker) - a real
  half-page-down move. Frame 128/130 (t=25.4-25.8s): after `u`, back to
  `apple-01`...`jackfruit-29` - the round trip confirmed. No internal path
  beyond the workspace label `ql-demo-hint` (the fixture dir's own basename);
  no client/Dwarves data.
