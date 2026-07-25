# Changelog

## Unreleased

- Fixed a line-jump regression: the bat filter briefly ran with a `header`
  row, and `less +N` counts lines in the FILTERED stream, so every
  `path:N` open landed one line off. The style is back to plain `numbers`
  (which is also what the file viewer itself runs), the filename moved into
  the pager footer via less's `%f`, and a test now pins one rendered row
  per source line.
- Review-batch follow-ups: the control-char filename guard runs before both
  viewer launch paths; the debug logger is shared, strips control bytes
  from untrusted token text and creates its log private; comments that
  asserted a since-disproven "panes get a minimal PATH" theory now say what
  was actually measured.

- The preview pane now paints a key footer along its bottom line
  (`q quit · o viewer · e edit · D diff · / search · space page`), so the
  bindings are discoverable instead of folklore. It rides less's own short
  prompt, so scrolling and the render registry are untouched, and the
  nested diff view gets its own footer because its keys differ. Hide it
  with an empty `QUICKLOOK_KEY_HINT`.

- A folder picked anywhere now opens in the file viewer, rooted at that
  folder, even outside the current repo. The plugin's own pane action can
  only ever root at the focused pane, so an outside target instead gets a
  plain tab created at it (`tab create --cwd`) with the viewer's binary run
  in it by absolute path; herdr injects no plugin context there, so the
  viewer roots at its own cwd. A file+line jump rides the viewer's
  `HERDR_FILE_VIEWER_OPEN` launch target, so that path needs no keystroke
  injection. Falls back to the preview when the viewer binary is not built.

- Reverted the cross-repo viewer re-root: it could never work. The viewer's
  manifest pane command is relative, so `pane open --cwd <dir>` made herdr
  look for its binary under that dir and the spawn failed outright; an
  injected context JSON is overridden by herdr, and the caller's cwd is
  ignored. The viewer always roots at the focused pane's repo. A target
  outside it now goes to the preview popup (which renders any path) with a
  notice, instead of a failed spawn.

- A DIRECTORY picked from the hint overlay opens the real file viewer again
  instead of a tree listing in the popup. The herdr server often runs with a
  minimal PATH, so a bare `herdr` is unreachable from the panes and actions
  it spawns; the dir handler's viewer gate then failed silently and downgraded
  the pick. lib.sh now resolves herdr_bin to an absolute install path when
  PATH cannot see it (and exports it to exec'd children), and the hint action
  answers the gate in its own context, passing QUICKLOOK_VIEWER_OK into the
  overlay so the routing decision needs no pane-side RPC at all.

- Review-batch fixes (advisor + security/architecture/test lenses over the
  session): escalate-editor/find-pane/recents-pane load env-only config (no
  wasted git+herdr forks); augment_roots' one plugin-list fork also captures
  the viewer root so render_markdown never re-queries; the cross-repo viewer
  re-root notifies where it rooted; bat theme flag shared via _bat_theme_flag;
  the not-found message mentions the workspace filename search; hint-pane's
  tty fallback probes openability (bare -r passes with no controlling tty).
  New tests: hint-pane bottom-align (headless stty stub), glow -w width,
  CLICOLOR_FORCE, viewer re-root failure + :line goto, oversized sweep guard.

- The hint overlay bottom-aligns the snapshot: the origin pane anchors its
  content to the bottom rows, so a snapshot shorter than the overlay pads
  blank rows on TOP instead of floating up and leaving a blank band below.
  Extras rows shrink the pad, mouse-click rows shift with it, and each
  repainted row clears to EOL so the shifted repaint leaves no tails.

- Viewer display parity for code: the bat theme pin is gone, so the user's
  own bat config decides the theme in BOTH panes (exactly how
  herdr-file-viewer invokes bat); QUICKLOOK_BAT_THEME now only adds a
  --theme flag when explicitly set. Renderer subprocesses get
  CLICOLOR_FORCE=1 (the viewer's trick) so piped tools keep full color.
  Code style is numbers,header (the viewer's gutter + a filename header).

- The hint scanner trims UNMATCHED wrapping punctuation: prose like
  `(assets/markdown-style.json copied ...)` splits the opener onto the span
  with its closer words away, so the token kept a leading `(` and never
  resolved. An opener with no closer in the span comes off the left, a
  closer with no opener off the right; spans holding both (`foo(1).md`,
  wiki-style URLs) stay untouched.

## 0.5.0 (2026-07-26)

- The bare-filename fallback (rung 7) widens to the workspace: when the
  current repo's tracked files have no hit, every first-level child repo of
  QUICKLOOK_ROOTS is searched (bounded, deduped, current repo skipped), so a
  cockpit row's bare filename opens from any pane.

- Installed herdr plugin roots join the implicit workspace roots, so a
  plugin-relative token (e.g. `assets/markdown-style.json`) resolves into
  the plugin's checkout under `~/.config/herdr/plugins/`.

- Markdown previews pick up herdr-file-viewer's bundled color palette when
  that plugin is installed, so the preview overlay and the viewer render
  markdown identically; `QUICKLOOK_GLOW_STYLE` (a glow style name or JSON
  file) overrides, fallback stays `auto`.
- Implicit workspace roots: the current repo root's parent and grandparent
  (`QUICKLOOK_PARENT_SWEEP`, default 2, 0 disables) are appended to
  `QUICKLOOK_ROOTS` at config load, so side-by-side repo layouts resolve
  cross-repo tokens with zero configuration on any machine.

- open-in-viewer no longer refuses a target outside the focused pane's repo:
  a cross-repo path (e.g. a cockpit row pointing into a sibling repo) opens a
  fresh viewer tab rooted at the target's own repo via `pane open --cwd`,
  then gotos the file as usual. Non-repo targets root at their directory.

- Markdown (and docx/xlsx/ipynb via the same path) no longer wraps at glow's
  hard piped default of 80 columns: `render_markdown` measures the pane's TTY
  and passes `-w`, so wide panes stop showing ragged orphan line fragments.

## 0.4.1 (2026-07-20)

- Demo roster pruned to living features only: removed the pick-anywhere,
  pluck-chain, linkify, and old overlay-keys recordings (their features were
  replaced by the hint picker in 0.4.0); kept tokens-tour and recents.
- README leads with the hero hint-flow demo and a one-sentence pitch.

## 0.4.0 (2026-07-20)

- UPPERCASE hint letter opens the pick in a full persistent tab pane;
  lowercase (and click) keep the 90% popup.

- The workspace sweep also probes each repo's house-standard worktrees
  (.claude/worktrees/*), so a gate-branch artifact opens from any pane; the
  not-found message now names every rung.

- Diff moved from `d` to `D` in the preview: lowercase `d` is less's own
  half-page-down and the old binding shadowed basic scrolling.

- A settled pick (hint key, mouse click, or the clipboard gate) now opens in
  herdr's 90% POPUP surface; the overlay is for choosing, the popup for
  reading. Plain left-click on a hinted token opens it (SGR mouse tracking
  inside the overlay - no Ctrl needed there).

- The three render-type demo tours (`render-images-tour.gif`,
  `render-docs-tour.gif`, `render-data-fallback.gif`) are re-recorded through
  the popup surface, matching the hero `hint-flow-tour.gif`.

- The bat header line is gone from the text renderer (the less status line
  already shows the full path, and the header wrapped on narrow overlays).

- Workspace sweep: a relative path referenced from another repo's pane
  resolves by probing each root's first-level children (root/<repo>/<path>),
  files and directories alike, as the last resolution rung.

- Five new render types (P2 pack): svg (`.svg`, `rsvg-convert` -> a temp png
  -> the same inline chafa render as still images), pdf (`.pdf`, a page-1
  poster via `pdftoppm`+chafa plus extracted text via `pdftotext`, paged
  together), archives (`zip`/`tar`/`tgz`/`jar`, a content listing via
  `unzip -l`/`tar -tf`), csv/tsv (`.csv`/`.tsv`, an aligned table via
  `qsv table`), and json (`.json`, pretty-printed via `jq .`). Each degrades
  cleanly without its tool: svg/csv/json (all textual content) fall to the
  plain-text preview, pdf degrades to text-only when only `pdftotext` is
  present, archives fall to the fallback guard below in the rare case
  `unzip`/`tar` are somehow absent (they are base-system).

- The preview overlay renders the P3 file types: Jupyter notebooks (`.ipynb`,
  via `pandoc`'s ipynb reader -> markdown -> `glow`), office documents
  (`docx`/`xlsx`, via `pandoc` -> markdown -> `glow`, `xlsx` shows its first
  sheet only), media (`mp4`/`mov`/`mp3`, `ffprobe` metadata plus a bounded
  `ffmpeg` first-frame poster for video - **never playback**), sqlite
  databases (`.sqlite`/`.db`, table list + schema via `sqlite3 -readonly` -
  never a row dump), and plists (`.plist`, `plutil -p`). Every kind degrades
  to plain text (for the text-shaped `.ipynb`) or the fallback guard below
  (for the binary-shaped kinds) when its tool is absent, never a crash or a
  raw-byte dump.

- Unknown/binary files now render through an always-on fallback guard: a
  `file(1)` type line, a bounded first-KB hexdump (`hexyl`, degrading to
  `xxd` then the base-system `od`), and an "install `<tool>`" hint when a
  richer renderer exists for the extension but its tool isn't installed -
  the floor every other v0.4 renderer degrades onto, so a preview never
  dumps a file's raw bytes into the terminal.

- New render type: markdown (`.md`/`.markdown`) renders via `glow` in the
  preview pane, paged; degrades to the plain-text preview when `glow` is
  absent (a markdown file is still perfectly readable as text).

- The preview overlay renders still images (`png`/`jpg`/`jpeg`/`webp`/`bmp`) and animated gifs inline via `chafa`: ANSI symbols mode by default (works in any terminal), with a kitty-graphics passthrough enhancement when the terminal signals support. Gifs animate via `chafa --animate` (bounded duration, never hangs the pane), falling back to a first-frame still when animation is unavailable. Both degrade to the fallback guard above (never a raw-byte dump) when `chafa` is absent.

- Bare domains (hermes.d.foundation, herdr.dev) classify as urls and open
  the browser with an https scheme, gated on a TLD allowlist so file
  extensions (.md, .go, .sh) never misclassify.

- A visible-but-unresolvable clipboard path now drops into the fzf finder
  pre-seeded as the query (partial/typo paths land on their closest match).

- New `find` action: fzf over tracked files with live bat preview; Enter
  renders the pick through the preview overlay.

- The `hint` picker replaces `pick`, `pluck-chain`, and the separate `linkify`
  overlay: one pluck-style in-place overlay (dim pane, one-letter hints on the
  token's first character, bright-yellow `#fffd01` badges), keyboard and
  Ctrl+click on the same open path, opened by type (file -> preview popup,
  directory -> file-viewer tab, URL -> browser).
- Clipboard-first immediate open: a copied token that is visible on screen and
  resolves opens instantly, no overlay; a stale clipboard never hijacks the key.
- Shape-first fast scan (tilde needs a slash, a lone-slash token must exist on
  disk), bare-name fuzzy off by default (`QUICKLOOK_HINT_NAMES=1` re-enables,
  `QUICKLOOK_HINT_VERIFIED=1` restores the verified scan).
- Tilde (`~/`) tokens resolve everywhere; the repo root itself is a valid
  viewer target; `open-in-viewer` opens the file viewer in its own tab.
- Fixed: plugin panes opened with `--cwd` flash-closed (herdr resolves the
  pane's relative command against it); every pane now receives its cwd via env.
  This also revived `recents` and `agent-suggestion`, broken the same way.

- Supported GitHub/GitLab/Bitbucket repository URLs now route through quicklook on Ctrl+click. The new `linkify` overlay reuses the pane scanner and renders paths, URLs, SHAs, refs, directories, and names as canonical OSC-8 links; `r` refreshes and `q`/`Esc` closes.
- Optional `pane.agent_status_changed` suggestions capture one baseline per working turn, scan only the completion delta, then notify or open the highest-confidence token. The latest suggestion can be reopened with the `agent-suggestion` action; the hook defaults to off and never polls pane output.
- Configuration examples add native `plugin_action` bindings for the new `linkify` and `agent-suggestion` actions.
- New `pick` action: lists every openable token currently on screen, no cap (ranked path > url > sha > ref > dir > name) with a count-by-kind header (`N on screen · A path · B url · ...`); the clipboard token is preselected as row 1 when it resolves; `Enter` opens the pick through the existing preview overlay, `Esc` closes without opening anything. Runs on any bash, including macOS's own `/bin/bash` (3.2) - the scan's tokenize/dedup/rank pipeline is awk-based rather than leaning on bash 4.3-only `local -n`/`local -A`.
- **Recommended keybinding**: `prefix+v` now points at `pick` instead of `preview` - `pick` needs no other plugin and is a superset of the old clipboard-only open; `preview` is still a valid action id to bind directly if you want the old behavior back.
- `pluck-chain`'s degrade (herdr-pluck absent, or its own invoke fails) now reroutes straight into the `pick` overlay instead of polling a clipboard that would never change; herdr-pluck stays fully optional.

## 0.3.0 (2026-07-17)

- `prefix+shift+y` chains herdr-pluck's hint overlay straight into the preview overlay: pick a token and it opens immediately, no separate keypress to consume the pick. Degrades to the plain clipboard flow when herdr-pluck isn't installed. Demo GIFs for every main use case (token dispatch, the three in-overlay keys, recents, the pluck chain) replace the single preview recording. (#15)
- Token dispatch refactored into a `scripts/lib.sh` entry point (`resolve_any_token`) plus a one-file-per-kind handler registry (`scripts/handlers/*.sh`); `RESOLVED_MODE` widened to `file` / `browser` / `command` / `viewer` so a token kind can render as a paged command or root a directory, not just open a file or a URL. Internal refactor, no user-facing behavior change on its own. (#7)
- GitHub blob/raw URLs (`github.com/o/r/blob/<ref>/<path>#L<n>`, `/raw/`, `raw.githubusercontent.com`) open the LOCAL checkout at the line when one resolves (current repo by name, plain resolve chain, `QUICKLOOK_ROOTS/<repo>`); refs containing `/` are handled by successive splits; unresolvable URLs fall back to the browser. `#L42-L60` ranges keep the start line. A crafted URL cannot smuggle an absolute or `..`-traversal path (guarded). (#5)
- GitLab (`gitlab.com/o/r/-/blob/<ref>/<path>#L<n>`) and Bitbucket (`bitbucket.org/o/r/src/<ref>/<path>#lines-<n>`) blob URLs resolve the same way, sharing the GitHub resolver and traversal guard. (#8)
- `e` in the preview overlay opens the current file, at the current line, in `$EDITOR` (config `QUICKLOOK_EDITOR` beats `$EDITOR` beats `zed --wait`); the overlay resumes once the editor exits. Bound via less's `pshell` shell-escape (a `^P`-suppressed `#` command), since the single `visual` slot is already `o`'s. (#6)
- `d` in the preview overlay opens a nested pager on `git diff` for the current file (delta-colored when installed, else git's own `--color=always`); pressing `d` again (or `q`) closes the diff and resumes the file view. Bound via less's `shell` action (the third and last available shell-escape slot, after `visual`/`o` and `pshell`/`e`); a clean file prints a no-changes notice instead of an empty diff. (#12)
- A bare commit SHA opens `git show` for that commit; `#123` or a GitHub PR URL opens `gh pr view`; both render in the popup's pager (`RESOLVED_MODE=command`). The token is always passed as a single argv element, never interpolated into a shell string. (#9)
- A directory token opens herdr-file-viewer rooted there when that plugin is installed, else an `eza --tree` (fallback `ls -la`) listing pages in the popup. (#11)
- `prefix+shift+v` reopens the most recently quick-looked path/URL/command, or fzf-picks among the last 20 when fzf is installed; the log is deduped (reopening bumps an entry back to the front), bounded, and lives outside any git repo at `${XDG_STATE_HOME:-~/.local/state}/herdr-quicklook/recents`. (#10)
- Agent-push: token priority is `$QUICKLOOK_TOKEN` env > script argument > clipboard, in both actions; `preview` forwards an argument into the pane via `--env`. Agents can now put a file on the human's screen without touching the clipboard. (#3)
- `resolve` always returns an absolute path (fixes a latent case where a cwd-relative hit failed open-in-viewer's repo-containment check).
- `open-in-viewer` refuses filenames containing control characters before typing them into the file-viewer TUI.
- bats test suite (`bats tests/`) over the resolve chain, token parsing, priority, the handler registry, and every in-popup key; shellcheck + bats documented as the dev loop. 154 cases across the series.

## 0.1.0 (2026-07-16)

Initial release.

- `preview` action: overlay pane rendering the clipboard's file path (bat as the LESSOPEN colorizer, plain less without it), opened at the right line for `path:123` tokens; URLs are handed to the default browser; bare filenames are resolved via the repo's tracked files (a single hit opens directly, several hits open an fzf pick, and without fzf the candidates are listed).
- Escalate from the overlay: `o` (or `v`) closes the quick look and opens the same file, at the line you scrolled to, inside the herdr-file-viewer pane.
- `open-in-viewer` action: the same hand-off straight from a keybinding, driving the viewer's fuzzy-find and goto-line keys over the herdr socket. Falls back to the preview overlay when herdr-file-viewer is not installed.
- Overlay keys: `q` or `Esc Esc` closes (a bare Esc binding cannot coexist with arrow-key scrolling in less), arrows and PgUp/PgDn scroll, `/` searches.
- Resolution chain: as-is, focused-pane cwd, every worktree of the current repo, configurable `QUICKLOOK_ROOTS`.
