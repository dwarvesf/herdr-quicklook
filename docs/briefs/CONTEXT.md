# Context for implementation

## Stack

Pure bash (no build step). herdr plugin: `herdr-plugin.toml` manifest + `scripts/*.sh`.
Rendering: `less` (668+) with `bat` as optional `LESSOPEN` colorizer, `fzf` optional,
`jq` required. Clipboard: `pbpaste`/`wl-paste`/`xclip` cascade. Platforms: linux + macos.
Tests: none yet (this spec adds bats).

## Conventions

- `scripts/lib.sh` holds shared helpers (sourced; keeps `.sh`); entry scripts are
  bash with `set -u`, shellcheck-clean (`shellcheck -x scripts/*.sh`).
- Degradation over failure: every optional dependency has a documented fallback
  (bat->less, fzf->list, file-viewer->preview overlay).
- Repo rule (CLAUDE.md): NO AI-attribution trailers in commits. Conventional
  Commits, subject <= 72 chars.
- Ship gate: docs/verification/README.md marker is installed; a behavioral change
  needs a proof of done before push.

## Key files

- `herdr-plugin.toml`, manifest: pane `preview` (overlay), actions `preview`,
  `open-in-viewer`.
- `scripts/lib.sh`, `clip_read`, `url_open`, `load_config`, `parse_token`
  (path:line split), `resolve` (as-is -> PWD -> worktrees -> QUICKLOOK_ROOTS).
- `scripts/open-preview.sh`, action: opens the overlay pane, forwards origin cwd.
- `scripts/preview-pane.sh`, pane: clipboard -> resolve -> less/bat render;
  bare-filename fallback via `git ls-files` + fzf; escalate via $VISUAL.
- `scripts/open-in-viewer.sh`, action: token from $1 or clipboard; drives
  herdr-file-viewer over the socket (send-keys f / send-text / :line).
- `scripts/escalate.sh`, $VISUAL target; parses `+LINE FILE`, calls
  open-in-viewer.sh, kills parent less to close the overlay.
- `lesskey`, `\e\e quit` (bare \e breaks arrow keys, verified on less 668).

## External dependencies

- herdr >= 0.7.0 socket CLI: `pane current/list/send-keys/send-text/zoom`,
  `plugin action invoke/list`, `plugin pane open`, `notification show`.
- herdr-file-viewer plugin (optional, for open-in-viewer).
- Reference for mechanics + gotchas:
  ops-toolkit `research/2026-07-16-herdr-token-open-pipeline.md`.
