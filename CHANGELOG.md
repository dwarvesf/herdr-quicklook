# Changelog

## 0.2.0 (2026-07-16)

- GitHub blob/raw URLs (`github.com/o/r/blob/<ref>/<path>#L<n>`, `/raw/`,
  `raw.githubusercontent.com`) now open the LOCAL checkout at the line when one
  resolves (current repo by name, plain resolve chain, `QUICKLOOK_ROOTS/<repo>`);
  refs containing `/` are handled by successive splits; unresolvable URLs fall
  back to the browser. `#L42-L60` ranges keep the start line.
- Agent-push: token priority is `$QUICKLOOK_TOKEN` env > script argument >
  clipboard, in both actions; `preview` forwards an argument into the pane via
  `--env`. Agents can now put a file on screen without touching the clipboard.
- `resolve` always returns an absolute path (fixes a latent bug where a
  cwd-relative hit failed open-in-viewer's repo-containment check).
- bats test suite (`bats tests/`) over the resolve chain, token parsing,
  classification, and priority; shellcheck + bats documented as the dev loop.

## 0.1.0 (2026-07-16)

Initial release.

- `preview` action: overlay pane rendering the clipboard's file path (bat as
  the LESSOPEN colorizer, plain less without it), opened at the right line for
  `path:123` tokens; URLs are handed to the default browser; bare filenames
  are resolved via the repo's tracked files (a single hit opens directly,
  several hits open an fzf pick, and without fzf the candidates are listed).
- Escalate from the overlay: `o` (or `v`) closes the quick look and opens the
  same file, at the line you scrolled to, inside the herdr-file-viewer pane.
- `open-in-viewer` action: the same hand-off straight from a keybinding,
  driving the viewer's fuzzy-find and goto-line keys over the herdr socket.
  Falls back to the preview overlay when herdr-file-viewer is not installed.
- Overlay keys: `q` or `Esc Esc` closes (a bare Esc binding cannot coexist
  with arrow-key scrolling in less), arrows and PgUp/PgDn scroll, `/` searches.
- Resolution chain: as-is, focused-pane cwd, every worktree of the current
  repo, configurable `QUICKLOOK_ROOTS`.
