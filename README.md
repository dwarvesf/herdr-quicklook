# herdr-quicklook

![platforms: linux • macOS](https://img.shields.io/badge/platforms-linux%20%E2%80%A2%20macOS-informational)
![herdr >= 0.7.0](https://img.shields.io/badge/herdr-%3E%3D%200.7.0-blueviolet)
[![license: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/dwarvesf/herdr-quicklook?style=flat&logo=github)](https://github.com/dwarvesf/herdr-quicklook/stargazers)

**Open whatever path or URL is on your clipboard, without leaving [herdr](https://herdr.dev).** Copy a token (a file path, `path:123`, a bare filename, an http(s) URL), hit one key, and it opens in the right place: an overlay preview pane, the [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) tree, or your browser.

Born from a daily annoyance: coding agents print file paths all day (`src/api/handler.go:142`), and reviewing one meant leaving the terminal or retyping the path. Pair this with a hint-copy plugin like [herdr-pluck](https://github.com/rmarganti/herdr-pluck) and the whole loop is two keystrokes: pluck the path, pop the file.

A few things that make it more than a pager:

- **A GitHub link opens your local file.** Paste `github.com/org/repo/blob/main/src/x.go#L42` and it opens *your checkout* at line 42, not a browser tab, resolving across worktrees and your other repos.
- **An agent can put a file on your screen.** Set `QUICKLOOK_TOKEN` and any script or coding agent pops a file into your overlay, no clipboard needed.
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

Then bind the two actions in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]              # overlay preview
key = "prefix+v"
type = "shell"
command = "herdr plugin action invoke preview --plugin herdr-quicklook"

[[keys.command]]              # open inside the file-viewer pane (optional)
key = "prefix+o"
type = "shell"
command = "herdr plugin action invoke open-in-viewer --plugin herdr-quicklook"

[[keys.command]]              # reopen a recent quicklook
key = "prefix+shift+v"
type = "shell"
command = "herdr plugin action invoke recents --plugin herdr-quicklook"

[[keys.command]]              # pluck a token, then quick-look it - one key
key = "prefix+shift+y"
type = "shell"
command = "herdr plugin action invoke pluck-chain --plugin herdr-quicklook"
```

Reload with `herdr server reload-config`.

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

Mechanically, herdr-pluck's only output channel is the system clipboard (there is no other IPC), so the chain fires the pluck action, polls the clipboard for a change, and forwards whatever lands there straight into the preview overlay via the same `QUICKLOOK_TOKEN` channel [agent-push](#agent-push-programmatic-tokens) uses. Without herdr-pluck installed, the binding degrades to the plain clipboard flow (identical to `preview`) instead of doing nothing.

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

Hard requirements: **herdr >= 0.7.0**, `jq`, and a clipboard reader (`pbpaste` on macOS, `wl-paste` or `xclip` on Linux).

Everything else is optional, and the plugin degrades instead of failing:

| Dependency | Used for | Without it |
|---|---|---|
| [`bat`](https://github.com/sharkdp/bat) | syntax-highlighted preview | plain `less` renders the file |
| [`fzf`](https://github.com/junegunn/fzf) | picking among multiple bare-filename matches | single matches still open; multiple matches are listed so you can copy an exact path |
| [herdr-file-viewer](https://github.com/smarzban/herdr-file-viewer) plugin | the `open-in-viewer` action | the action falls back to the preview overlay automatically |
| [herdr-pluck](https://github.com/rmarganti/herdr-pluck) plugin | the `pluck-chain` action (recommended pairing) | `pluck-chain` degrades to the plain clipboard flow; any other way of copying a path works the same |

## How it works

- **preview** opens a plugin overlay pane (a real TTY) that reads the clipboard, resolves the token through the [handler registry](DESIGN.md#handler-registry), and renders it per `RESOLVED_MODE`: a `file` opens in `less` (bat as the `LESSOPEN` colorizer), a `browser` URL is handed to `url_open` and the overlay closes, a `command` token (vcs) or `viewer` degrade (a directory without herdr-file-viewer installed) pages its output through `less -R`. Esc-to-quit and the three in-popup shell-escapes ship via a `lesskey` file: `o` escalates via less's single `visual` slot (`$VISUAL` -> `escalate.sh`); `e` and `d` cannot reuse that slot, so `e` is bound to less's `pshell` action (`escalate-editor.sh`) and `d` to its `shell` action (`dirty-diff.sh`), each with a `^P` extra-string prefix that suppresses the shell-escape's normal "done" prompt so the overlay resumes cleanly. See [DESIGN.md](DESIGN.md#the-lesskey-three-slot-map) for why there are only three slots to go around.
- **open-in-viewer** has no goto-file API to call, so it drives the viewer's own keys over the herdr socket: it ensures a `Files` pane exists in the focused tab (opening one via the viewer's action if needed), then sends `f`, types the repo-relative path, and presses Enter; `path:123` follows up with the viewer's `:` goto-line. A directory token reuses the same goto-path sequence to root the viewer there. This is UI-scripting by nature: if the viewer's keymap changes upstream, this action needs a revisit.
- **recents** has no TTY of its own either (herdr runs every action's command headless), so it opens a second overlay pane (`recents-pick`) just for the fzf pick; the chosen entry is then handed to the SAME `preview` overlay-rendering code (`preview-pane.sh`, `exec`'d in place, not a third pane) so a reopened entry resolves and records exactly like a fresh open.
- **pluck-chain** fires herdr-pluck's own `pluck` action (its hint-overlay picker is a separate temporary tab with its own TTY, so this action cannot wait on it directly) and polls the clipboard - herdr-pluck's only output channel - for the pick, then forwards it straight into `preview` via `QUICKLOOK_TOKEN`.
- No event hooks, no daemons, nothing runs until you press your key.

Full architecture, the token-flow diagram, and the handler contract for adding a new token kind: [DESIGN.md](DESIGN.md).

## Limitations

- One token at a time: it reads the clipboard, it does not scan the screen (that is the hint-copy plugin's job).
- `open-in-viewer` only reaches files inside the focused pane's repo (the viewer roots there); anything outside gets a notification pointing at the preview overlay instead.
- GitHub-URL resolution matches the URL's `<repo>` against the **current checkout's directory name**. If two unrelated local repos share a directory name it can open the same-named file in the wrong one; a URL for a repo you have no local checkout of falls back to the browser.
- Windows is untested (clipboard/opener cascades cover macOS + Linux).

## License

MIT
