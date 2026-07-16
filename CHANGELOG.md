# Changelog

## 0.1.0 (2026-07-16)

Initial release.

- `preview` action: overlay pane rendering the clipboard's file path (bat as the LESSOPEN colorizer, plain less without it), opened at the right line for `path:123` tokens; URLs are handed to the default browser; bare filenames are resolved via the repo's tracked files (a single hit opens directly, several hits open an fzf pick, and without fzf the candidates are listed).
- Escalate from the overlay: `o` (or `v`) closes the quick look and opens the same file, at the line you scrolled to, inside the herdr-file-viewer pane.
- `open-in-viewer` action: the same hand-off straight from a keybinding, driving the viewer's fuzzy-find and goto-line keys over the herdr socket. Falls back to the preview overlay when herdr-file-viewer is not installed.
- Overlay keys: `q` or `Esc Esc` closes (a bare Esc binding cannot coexist with arrow-key scrolling in less), arrows and PgUp/PgDn scroll, `/` searches.
- Resolution chain: as-is, focused-pane cwd, every worktree of the current repo, configurable `QUICKLOOK_ROOTS`.
