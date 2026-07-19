#!/usr/bin/env bash
# Pane `recents-pick`: runs inside an overlay (real TTY, same placement as
# the `preview` pane). Opened by the `recents` action (scripts/recents.sh),
# which has no TTY of its own to run fzf from - see the header comment
# there.
#
# No fzf installed: reopens the most recent entry directly, no interactive
# step (the goal's stated degrade). fzf installed: presents the recents log
# (most-recent-first) for a pick. Either way, the chosen raw token is handed
# to preview-pane.sh via QUICKLOOK_TOKEN and `exec`'d IN THIS SAME PANE/TTY
# (not a new pane) - reusing preview-pane.sh's own resolve+render+
# record_open logic verbatim means a reopened recents entry is itself
# recorded again, which is exactly the recency-bump dedup semantic
# record_open already implements (see lib.sh).
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
. "$script_dir/lib.sh"

load_config

# Enter the origin repo (forwarded as env, never --cwd: --cwd flash-closes
# the pane) so a relative recents entry resolves against the right repo.
if [ -n "${QUICKLOOK_PREVIEW_CWD:-}" ] && [ -d "$QUICKLOOK_PREVIEW_CWD" ]; then
  cd "$QUICKLOOK_PREVIEW_CWD" || true
fi

pause_close() {
  printf '%s\n' "$*"
  read -r -n1 -p "press any key to close" _ 2>/dev/null || sleep 2
  exit 0
}

candidates=()
while IFS= read -r line; do
  [ -n "$line" ] && candidates+=("$line")
done < <(recents_list)

[ "${#candidates[@]}" -eq 0 ] && pause_close "quicklook: no recents yet"

if command -v fzf >/dev/null 2>&1; then
  pick="$(printf '%s\n' "${candidates[@]}" | fzf --prompt="recents ▸ " --reverse --cycle --height=100%)" || exit 0
  [ -z "$pick" ] && exit 0
else
  # No fzf: reopen the most recent (candidates[0], recents_list is
  # already most-recent-first) with no interactive step.
  pick="${candidates[0]}"
fi

export QUICKLOOK_TOKEN="$pick"
exec bash "$script_dir/preview-pane.sh"
