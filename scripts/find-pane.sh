#!/usr/bin/env bash
# Pane `find-pane`: the fuzzy file finder overlay (real TTY). Opened by the
# `find` action (scripts/find.sh), which forwarded the origin repo cwd.
#
# fzf over the repo's tracked files (git ls-files; outside a repo, a bounded
# find), with a live bat preview while typing. Enter hands the pick to
# preview-pane.sh via QUICKLOOK_TOKEN, exec'd IN THIS SAME PANE, so the file
# resolves + renders + records exactly like every other quicklook open (and
# the o/e/d escalation keys keep working). Esc closes.
#
# No herdr RPC here (a server RPC from a server-spawned overlay pane
# deadlocks); git/fzf/bat are all local.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
. "$script_dir/lib.sh"

load_config

if [ -n "${QUICKLOOK_FIND_CWD:-}" ] && [ -d "$QUICKLOOK_FIND_CWD" ]; then
  cd "$QUICKLOOK_FIND_CWD" || true
fi

tty_in=/dev/tty
[ -r "$tty_in" ] || tty_in=/dev/stdin

pause_close() {
  printf '%s\n\n(press any key to close)' "$*"
  read -rsn1 _ <"$tty_in" 2>/dev/null || sleep 2
  exit 0
}

command -v fzf >/dev/null 2>&1 || pause_close "quicklook find needs fzf (brew install fzf)"

# File list: tracked files when inside a repo (fast, no noise), else a
# bounded find. ponytail: depth 6 cap outside repos, tune if it ever bites.
list_files() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git ls-files
  else
    find . -maxdepth 6 -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||'
  fi
}

preview_cmd='bat --color=always --style=numbers {} 2>/dev/null || cat {} 2>/dev/null'
command -v bat >/dev/null 2>&1 || preview_cmd='cat {} 2>/dev/null'

# QUICKLOOK_FIND_QUERY pre-seeds the fzf query: the hint flow drops an
# on-screen-but-unresolvable clipboard path here, so a partial/typo path
# lands pre-filtered to its closest matches.
pick="$(list_files | fzf \
  --prompt="quicklook find ▸ " --reverse --height=100% \
  --query "${QUICKLOOK_FIND_QUERY:-}" \
  --preview "$preview_cmd" --preview-window='right,60%,border-left')" || exit 0
[ -z "$pick" ] && exit 0

export QUICKLOOK_TOKEN="$pick"
exec bash "$script_dir/preview-pane.sh"
