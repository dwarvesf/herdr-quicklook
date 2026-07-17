# herdr-quicklook

![platforms: linux • macOS](https://img.shields.io/badge/platforms-linux%20%E2%80%A2%20macOS-informational)
![herdr >= 0.7.0](https://img.shields.io/badge/herdr-%3E%3D%200.7.0-blueviolet)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/dwarvesf/herdr-quicklook?style=flat&logo=github)](https://github.com/dwarvesf/herdr-quicklook/stargazers)

**Open whatever path or URL an agent puts in front of you, without leaving [herdr](https://herdr.dev).** Copy a token (a file path, `path:123`, a bare filename, an http(s) URL), hit one key, and it opens in the right place: an overlay preview pane, the [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) tree, or your browser. Supported repository URLs work with Ctrl+click directly; the link overlay makes bare paths and every other detected token Ctrl+clickable too.

Born from a daily annoyance: coding agents print file paths all day (`src/api/handler.go:142`), and reviewing one meant leaving the terminal or retyping the path. Pair this with a hint-copy plugin like [herdr-pluck](https://github.com/rmarganti/herdr-pluck) and the whole loop is two keystrokes: pluck the path, pop the file.

A few things that make it more than a pager:

- **A GitHub link opens your local file.** Paste `github.com/org/repo/blob/main/src/x.go#L42` and it opens *your checkout* at line 42, not a browser tab, resolving across worktrees and your other repos.
- **Ctrl+click links without changing herdr.** Repository URLs route through quicklook directly. For bare paths, the link overlay snapshots the focused pane and renders every resolvable token as an OSC-8 link.
- **An agent can put a file on your screen.** Set `QUICKLOOK_TOKEN` directly, or opt into agent suggestions that scan only output produced during the latest working turn.
- **Quick look, then commit to it.** Reading in the overlay and want the full tree? One key (`o`) escalates the same file, at the same line, into [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer).
- **Or straight into your editor.** `e` opens the same file, at the same line, in `$EDITOR` (config-overridable); the overlay resumes once you close it.

## What it opens

| Clipboard content | What happens |
|---|---|
| a GitHub / GitLab / Bitbucket **blob or raw URL** (`github.com/o/r/blob/main/x.go#L42`, `gitlab.com/o/r/-/blob/main/x.go#L42`, `bitbucket.org/o/r/src/main/x.go#lines-42`, `raw.githubusercontent.com/…`) | Opens the file in your **local checkout** at that line when one exists (current repo, worktrees, `QUICKLOOK_ROOTS/<repo>`); otherwise the browser |
| a bare commit **SHA** (7-40 hex chars) | `git show` for that commit, paged in the popup |
| `#123`, or a GitHub **PR URL** (`github.com/o/r/pull/123`) | `gh pr view`, paged in the popup |
| any other `https://…` / `http://…` | Opens in your default browser |
| `/absolute/path/file.md` | Preview (or viewer) at that file |
| `relative/path/file.md` | Resolved against the focused pane's cwd, then its git root |
| a path from **another worktree** of the same repo | Resolved via `git worktree list`, both directions |
| `path/file.md:123` | Opens with line 123 highlighted (`:123` jump in the viewer) |
| a path under one of your `QUICKLOOK_ROOTS` | Resolved against each configured root |
| `filename.md` (bare, no directory) | Repo-wide search of tracked files: one hit opens; several hits open an fzf pick |
| `some/dir` (a directory, not a file) | Opens herdr-file-viewer rooted there when installed, else an `eza --tree`/`ls -la` listing in the popup |

Resolution runs top-down: exact paths win before any fuzzy matching, and the first hit stops the chain. See [DESIGN.md](DESIGN.md) for how a token kind maps to its handler.

## Install

```sh
herdr plugin install dwarvesf/herdr-quicklook
```

Bind whichever actions you want in `~/.config/herdr/config.toml`. Native `plugin_action` bindings preserve herdr's plugin context and avoid an extra shell/CLI hop:

```toml
[[keys.command]]              # pick anything openable on screen - the unified entry
key = "prefix+v"
type = "plugin_action"
command = "herdr-quicklook.pick"

[[keys.command]]              # open inside the file-viewer pane (optional)
key = "prefix+o"
type = "plugin_action"
command = "herdr-quicklook.open-in-viewer"

[[keys.command]]              # reopen a recent quicklook
key = "prefix+shift+v"
type = "plugin_action"
command = "herdr-quicklook.recents"

[[keys.command]]              # pluck a token (needs herdr-pluck), then quick-look it -
                               # falls back to the same pick overlay above when
                               # herdr-pluck is absent or its invoke fails
key = "prefix+shift+y"
type = "plugin_action"
command = "herdr-quicklook.pluck-chain"

[[keys.command]]              # render pane tokens as Ctrl-clickable links
key = "prefix+shift+l"
type = "plugin_action"
command = "herdr-quicklook.linkify"

[[keys.command]]              # open the latest opt-in agent suggestion
key = "prefix+shift+a"
type = "plugin_action"
command = "herdr-quicklook.agent-suggestion"
```

Reload with `herdr server reload-config`.

`pick` needs no other plugin, so it is the recommended `prefix+v` binding
above; `preview` (opens the clipboard token directly, no scan) is still a
valid action id if you'd rather bind that directly instead, and `pick` can
just as easily live on its own key (e.g. `prefix+shift+p`) alongside it.

## Keys in the preview overlay

| Key | Does |
|---|---|
| `q` or `Esc Esc` | Close the overlay (a bare Esc cannot coexist with arrow-key scrolling in less, so quit is double-Esc) |
| `o` (or `v`) | **Escalate**: close the overlay and open this file, at the same line, in the herdr-file-viewer pane (when that plugin is installed) |
| `e` | **Edit**: open this file, at the same line, in `$EDITOR` (config-overridable, default `zed --wait`); the overlay resumes when the editor exits |
| `d` | **Diff**: open a nested pager on `git diff` for this file (delta-colored if installed, else git's own color); press `d` again (or `q`) to close it and resume the file view. A clean file just prints a no-changes notice |
| `/`, `n`, `N` | Search inside the file |
| arrows / PgUp / PgDn | Scroll |

The overlay is sized by herdr; it closes itself after handing a URL to the browser.

## Recents (`prefix+shift+v`)

Every successful open (a file, a URL, a `command`/`viewer`-mode result) is recorded to a small, bounded log (last 20, deduped: reopening something already in the log just moves it back to the front). Press the binding and it reopens the most recent entry directly; with [`fzf`](https://github.com/junegunn/fzf) installed and more than one entry, it opens an fzf pick over the last N instead.

The log lives outside any git repo, at `${XDG_STATE_HOME:-~/.local/state}/herdr-quicklook/recents`, never inside your working tree. Recording is best-effort: a write failure (unwritable state dir, or the guard above refusing a path that resolved inside a repo) never blocks the open it was trying to record.

## One-key pluck chain (`prefix+shift+y`)

Pairs this plugin with [herdr-pluck](https://github.com/rmarganti/herdr-pluck) as one action instead of two keystrokes. Press the binding and herdr-pluck's Vimium-style hint labels appear over every copyable token in the pane; type a hint and the picked token opens in the preview overlay immediately, no separate `prefix+v` needed to consume it.

Mechanically, herdr-pluck's only output channel is the system clipboard (there is no other IPC), so the chain fires the pluck action, polls the clipboard for a change, and forwards whatever lands there straight into the preview overlay via the same `QUICKLOOK_TOKEN` channel [agent-push](#agent-push-programmatic-tokens) uses. Without herdr-pluck installed - or if herdr-pluck's own invoke fails - the binding reroutes straight into the `pick` overlay below instead of stalling on a clipboard poll that would never resolve.

## Pick anything on screen (`prefix+v`)

Lists every openable token currently visible in the pane, ranked by confidence (a resolvable path first, then URLs, commit SHAs, `#refs`, directories, and unique bare filenames last), with a count-by-kind header (e.g. `N on screen · A path · B url · C sha · D dir`, listing only the kinds actually present). Every openable token currently visible is counted and listed; there is no cap. If the clipboard already holds a token that resolves, it is preselected as row 1 (labeled `clipboard: <token>`) and deduped out of the on-screen list below it. `Enter` opens the highlighted pick through the same preview overlay as every other open; `Esc` closes without opening anything. With no [`fzf`](https://github.com/junegunn/fzf) installed, the top row opens directly, no interactive step.

## Ctrl-click and the link overlay (`prefix+shift+l`)

Herdr already recognizes visible http(s) URLs. This plugin registers narrow link handlers for the repository URL shapes it can improve: GitHub blob/raw and PR URLs, GitLab blob URLs, and Bitbucket source URLs. Ctrl+click one and it follows the normal quicklook resolver, opening a local checkout or `gh pr view` when possible before falling back to the browser.

A plain `src/api/handler.go:142` in another pane is not a URL, so a plugin cannot make that original cell clickable. The `linkify` action works around that boundary without patching herdr: it reads a snapshot of the focused pane, reuses the same scanner as `pick`, and renders its ranked candidates as OSC-8 links in an overlay. Ctrl+click a label to open it; `r` refreshes from the origin pane and `q` or `Esc` closes. Closing a nested preview returns to the link list, making it convenient to inspect several paths.

The sentinel URLs use the reserved `.invalid` domain and are accepted only after a canonical encode/decode check. They are an internal transport between the overlay and this plugin's link handler, never a network destination.

## Agent suggestions (opt-in)

Set `QUICKLOOK_AGENT_SUGGESTIONS=notify` to watch herdr's low-volume `pane.agent_status_changed` event. When an agent starts working, quicklook records a transcript baseline. When it reaches `done` or `idle`, only text added during that turn is scanned; the highest-confidence token is saved as the latest suggestion and shown in a herdr notification. The `agent-suggestion` action opens it later using the producing pane's cwd.

Set the value to `preview` instead to open the detected token immediately. This can steal focus when a background agent finishes, so `notify` is the recommended mode and the feature defaults to `off`. Repeated presentation events are deduped, and no polling process or output-change daemon is started.

## Configuration

Optional. Create `.env` in the directory `herdr plugin config-dir herdr-quicklook` prints:

```sh
# Extra roots to try for relative paths, colon-separated. Useful when tools
# print repo-prefixed paths like "myrepo/docs/notes.md" and all your repos
# live under one parent directory.
QUICKLOOK_ROOTS="$HOME/workspace:$HOME/src"

# Command launched by `e` in the overlay. Precedence: this key > $EDITOR >
# "zed --wait". Set it here rather than relying on $EDITOR alone: the herdr
# server process that launches this pane does not reliably inherit an
# interactive shell's exported vars.
QUICKLOOK_EDITOR="zed --wait"

# Optional agent completion suggestions: off (default), notify, or preview.
# `preview` opens an overlay immediately and may interrupt the active pane.
QUICKLOOK_AGENT_SUGGESTIONS="notify"

# Number of recent unwrapped pane lines retained for per-turn baselines.
QUICKLOOK_AGENT_SCAN_LINES=300
```

## Agent-push (programmatic tokens)

The plugin reads, in priority order: `$QUICKLOOK_TOKEN` env > script argument > clipboard. That gives an agent (or any script) a way to put a file on the human's screen without touching their clipboard:

```sh
# pop the overlay for a specific file+line
herdr plugin pane open --plugin herdr-quicklook --entrypoint preview \
  --placement overlay --focus --env QUICKLOOK_TOKEN="src/handler.go:142"
```

An empty `QUICKLOOK_TOKEN` is treated as unset; the interactive clipboard flow is unchanged when neither env nor argument is given.

## Development

```sh
shellcheck -x scripts/*.sh && bats tests/   # brew install shellcheck bats-core
```

The bats suite sources `scripts/lib.sh` directly (temp git repo + worktree + roots fixture), so it exercises the exact production resolve chain.

## Release

Maintainer-only, run by hand, no CI trigger:

```sh
./scripts/release.sh 0.3.0
```

One command: sanity checks (clean tree, on `main`, shellcheck + bats green, tag
doesn't already exist), bumps `herdr-plugin.toml`'s version, moves
`CHANGELOG.md`'s `## Unreleased` section into a dated `## 0.3.0 (…)` section,
commits `chore(release): v0.3.0`, tags it, pushes commit + tag, and cuts a
GitHub release (`gh release create`) with that changelog section as the notes
body. Refuses to run against a dirty tree, a non-`main` branch, or an
already-tagged version.

## Demo

**Ctrl+click bare paths without an upstream change** - `prefix+shift+l` snapshots the focused pane into a link overlay; a real Ctrl+click opens `scripts/linkify-pane.sh:30` locally, closing the preview returns to the link list, and the original GitHub blob URL Ctrl+clicks straight into the local checkout too:

![linkify: bare pane paths become OSC-8 links, Ctrl-click opens a local preview, and repository URLs route through quicklook directly](demo/linkify.gif)

**Pick anything on screen** - `prefix+v` on a busy pane (real commits, `ls`, a URL) opens the ranked, count-headered pick list; a pick opens in the preview overlay. Plus the negative control: an empty pane and an empty clipboard yield the honest "nothing openable on screen" instead of a crash:

![pick anywhere: prefix+v scans a busy pane, shows the count header, opens a pick in the preview overlay; then the negative control, an empty pane yields the honest empty-state message](demo/pick-anywhere.gif)

**Every token kind in one pass** - a plain path, a GitHub blob URL (opens the local file), a bare commit SHA (`git show`), a `#123` PR reference (`gh pr view`), a directory (`eza --tree`):

![tokens tour: path, GitHub blob URL, commit SHA, PR reference, and a directory, all opened from the clipboard](demo/tokens-tour.gif)

**The three in-overlay keys** - `d` (dirty-diff toggle), `e` (edit in `$EDITOR`), `o` (escalate to herdr-file-viewer):

![overlay keys tour: d toggles a git diff, e opens $EDITOR, o escalates into herdr-file-viewer](demo/overlay-keys-tour.gif)

**Recents** - fzf-pick an older entry; reopening bumps it back to the front:

![recents: open two files, then fzf-pick the older one back into view](demo/recents.gif)

**The one-key pluck chain** - herdr-pluck's hint overlay pops, pick a token, quick-look opens it immediately:

![pluck full flow: hint labels appear over visible tokens, pick one, and it opens with no extra keypress](demo/pluck-full-flow.gif)

Tapes for every recording live in [demo/](demo/), along with the landmines hit re-recording them on macOS.

## Requirements

Hard requirements: **herdr >= 0.7.0**, `jq`, and a clipboard reader (`pbpaste` on macOS, `wl-paste` or `xclip` on Linux). Every action, including scanner-backed `pick`, `linkify`, and enabled agent suggestions, runs under the system bash - macOS's own `/bin/bash` (3.2) is fully supported, no Homebrew `bash` required.

Everything else is optional, and the plugin degrades instead of failing:

| Dependency | Used for | Without it |
|---|---|---|
| [`bat`](https://github.com/sharkdp/bat) | syntax-highlighted preview | plain `less` renders the file |
| [`fzf`](https://github.com/junegunn/fzf) | picking among multiple bare-filename matches, and the `pick` overlay's interactive list | single bare-filename matches still open, multiple are listed so you can copy an exact path; `pick`'s top-ranked row (or the resolved clipboard token) opens directly with no interactive step |
| [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) plugin | the `open-in-viewer` action | the action falls back to the preview overlay automatically |
| [herdr-pluck](https://github.com/rmarganti/herdr-pluck) plugin | the `pluck-chain` action (recommended pairing) | `pluck-chain` reroutes into the native `pick` overlay instead of stalling |

## How it works

- **preview** opens a plugin overlay pane (a real TTY), reads `$QUICKLOOK_TOKEN`, an argument, or the clipboard, resolves it through the [handler registry](DESIGN.md#handler-registry), and renders it per `RESOLVED_MODE`: a `file` opens in `less` (bat as the `LESSOPEN` colorizer), a `browser` URL is handed to `url_open` and the overlay closes, a `command` token (vcs) or `viewer` degrade (a directory without herdr-file-viewer installed) pages its output through `less -R`. Esc-to-quit and the three in-popup shell-escapes ship via a `lesskey` file: `o` escalates via less's single `visual` slot (`$VISUAL` -> `escalate.sh`); `e` and `d` cannot reuse that slot, so `e` is bound to less's `pshell` action (`escalate-editor.sh`) and `d` to its `shell` action (`dirty-diff.sh`), each with a `^P` extra-string prefix that suppresses the shell-escape's normal "done" prompt so the overlay resumes cleanly. See [DESIGN.md](DESIGN.md#the-lesskey-three-slot-map) for why there are only three slots to go around.
- **open-in-viewer** has no goto-file API to call, so it drives the viewer's own keys over the herdr socket: it ensures a `Files` pane exists in the focused tab (opening one via the viewer's action if needed), then sends `f`, types the repo-relative path, and presses Enter; `path:123` follows up with the viewer's `:` goto-line. A directory token reuses the same goto-path sequence to root the viewer there. This is UI-scripting by nature: if the viewer's keymap changes upstream, this action needs a revisit.
- **recents** has no TTY of its own either (herdr runs every action's command headless), so it opens a second overlay pane (`recents-pick`) just for the fzf pick; the chosen entry is then handed to the same `preview` overlay-rendering code (`preview-pane.sh`, `exec`'d in place, not a third pane) so a reopened entry resolves and records exactly like a fresh open.
- **pluck-chain** fires herdr-pluck's own `pluck` action (its hint-overlay picker is a separate temporary tab with its own TTY, so this action cannot wait on it directly) and polls the clipboard - herdr-pluck's only output channel - for the pick, then forwards it straight into `preview` via `QUICKLOOK_TOKEN`. When herdr-pluck is absent, or its own invoke fails, this reroutes into `pick` instead of polling a clipboard that will never change.
- **pick** captures the origin pane id before opening its own overlay (`pane current` would return the overlay itself once it has focus, not the pane you were looking at), then that overlay pane reads the origin pane's on-screen text (`herdr pane read --format text`), tokenizes it, classifies each span through the same [handler registry](DESIGN.md#handler-registry) `resolve_any_token` walks (via pure scan-local mirrors of the real handlers, so scanning stays fast and never mutates any handler's resolve-time globals), and ranks the result. `Enter` hands the chosen raw token to the same `preview-pane.sh` rendering code every other open uses.
- **linkify** captures the origin pane before opening `linkify-pane`; that overlay runs the existing pure scanner, encodes each token into a canonical `.invalid` sentinel URL, and emits OSC-8 labels. Herdr's native Ctrl-click resolver invokes `open-link`, which decodes the token and routes it back through `preview`.
- **agent suggestions** use one low-volume herdr status hook, not an output hook or polling process. The hook exits immediately by default; when enabled, it stores a per-pane baseline at `working`, scans the completion delta at `done`/`idle`, and writes the newest suggestion under Herdr's plugin state directory.

Full architecture, the token-flow diagram, and the handler contract for adding a new token kind: [DESIGN.md](DESIGN.md).

## Limitations

- Herdr only sends Ctrl-clicks for http(s) cells to plugin handlers. Bare paths in the original pane therefore require `linkify`, `pick`, pluck, or the clipboard flow; quicklook cannot alter another pane's rendered cells.
- `preview`/`open-in-viewer`/`recents`/`pluck-chain` still consume one token at a time; `pick` and `linkify` scan pane text.
- `pick` and `linkify` scan the pane's visible text by default (`QUICKLOOK_PICK_SOURCE=recent` or `recent-unwrapped` opts into scrollback); they do not read inside `less`/`bat`'s own paged output or a nested pane.
- Agent suggestions scan only the configured recent-unwrapped turn window and depend on herdr detecting the pane as an agent and observing a `working` event before `done`/`idle`. A completion with no recorded baseline intentionally produces no stale suggestion.
- `open-in-viewer` only reaches files inside the focused pane's repo (the viewer roots there); anything outside gets a notification pointing at the preview overlay instead.
- GitHub-URL resolution matches the URL's `<repo>` against the **current checkout's directory name**. If two unrelated local repos share a directory name it can open the same-named file in the wrong one; a URL for a repo you have no local checkout of falls back to the browser.
- Windows is untested (clipboard/opener cascades cover macOS + Linux).

## License

MIT
