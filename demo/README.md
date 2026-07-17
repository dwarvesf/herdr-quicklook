# demo/

Five GIFs, recorded from a real herdr session with [vhs](https://github.com/charmbracelet/vhs),
covering every main use case:

| GIF | Shows |
|---|---|
| `tokens-tour.gif` | Every token kind in one pass: a plain path, a GitHub blob URL (opens the local file), a bare commit SHA (`git show`), a `#123` PR reference (`gh pr view`), a directory (`eza --tree`) |
| `overlay-keys-tour.gif` | The three in-overlay keys: `d` (dirty-diff toggle), `e` (edit in `$EDITOR`), `o` (escalate to herdr-file-viewer) |
| `recents.gif` | `prefix+shift+v`: fzf-pick an older entry, proving the reopen bumps it back to the front |
| `pluck-full-flow.gif` | The one-key pluck chain: herdr-pluck's hint overlay pops, pick a token, quick-look opens it immediately, no extra keypress |
| `pick-anywhere.gif` | `prefix+v` on a busy pane (real commits, `ls`, a URL): `pluck-chain` reroutes into the native `pick` overlay (herdr-pluck not linked), the count header (`N on screen · A path · B url · ...`) is visible, a pick opens in the preview overlay. Plus the negative control: an empty pane and an empty clipboard yield the honest `quicklook: nothing openable on screen` instead of a crash or silent no-op |

## Recording

```sh
git clone <this repo> /private/tmp/demo/herdr-quicklook   # NOT /tmp/... (see below)
cd /private/tmp/demo/herdr-quicklook
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
- **verified**: one-dark theme (both takes), main take shows a genuinely busy pane
  (3 real commit SHAs via `git --no-pager log`, real repo file/dir names via `ls`, a
  real URL); this take's count header renders `18 on screen · 8 path · 1 url · 3
  sha · 3 dir · 3 name` (what THIS specific recording's busy pane produced, not a
  general capacity figure - `pick` has no cap), and a real pick (`LICENSE`) opens
  in the preview overlay; negative control shows the honest `quicklook: nothing
  openable on screen` on a cleared pane with an empty clipboard. No internal paths
  beyond the scratch clone's own `/private/tmp/demo/...` directory name; no
  client/Dwarves data.
