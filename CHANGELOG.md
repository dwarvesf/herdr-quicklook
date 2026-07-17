# Changelog

## Unreleased

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
