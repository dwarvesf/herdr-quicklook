#!/usr/bin/env bash
# Pane `pick-pane`: runs inside an overlay (real TTY, same placement as the
# `preview` pane). Opened by the `pick` action (scripts/pick.sh), which has
# no TTY of its own to run fzf from - see the header comment there. Mirrors
# scripts/recents-pane.sh's action/pane split.
#
# Lists everything openable currently on screen in the ORIGIN pane - the
# pane pick.sh captured BEFORE this overlay stole focus, forwarded via
# QUICKLOOK_PICK_ORIGIN_PANE (herdr pane current would return THIS overlay
# by the time this script runs, not the origin - see HANDOFF.md). Ranking
# comes from pick_acquire/pick_scan_text (lib.sh). Row 1 is the clipboard
# token when it resolves (label `clipboard: <tok>`, preselected - fzf
# --reverse starts the pointer on row 1, so Enter opens it immediately);
# rows 2..N are the ranked on-screen candidates, with the clipboard token
# deduped out of them. Enter hands the chosen raw token to preview-pane.sh
# via QUICKLOOK_TOKEN, `exec`'d IN THIS SAME PANE/TTY (not a new pane) -
# identical hand-off to recents-pane.sh, so a pick resolves/renders/records
# exactly like any other open.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
. "$script_dir/lib.sh"

load_config

pause_close() {
  printf '%s\n' "$*"
  read -r -n1 -p "press any key to close" _ 2>/dev/null || sleep 2
  exit 0
}

# fzf row shape: <raw-token>\t<display label> - a hidden raw column plus
# the shown label (--delimiter/--with-nth below), so a labeled clipboard
# row still carries its real token through to Enter.
rows=()

clip="${QUICKLOOK_PICK_CLIP:-}"
clip_resolved=0
if [ -n "$clip" ] && resolve_any_token "$clip" >/dev/null 2>&1; then
  clip_resolved=1
  rows+=("$(printf '%s\t%s' "$clip" "clipboard: $clip")")
fi

scan_output="$(pick_acquire "${QUICKLOOK_PICK_ORIGIN_PANE:-}")"
header="$(pick_count_header <<<"$scan_output")"

while IFS=$'\t' read -r raw _ _; do
  [ -z "$raw" ] && continue
  # Dedup: the clipboard row above already carries this raw token.
  [ "$clip_resolved" -eq 1 ] && [ "$raw" = "$clip" ] && continue
  rows+=("$(printf '%s\t%s' "$raw" "$raw")")
done <<<"$scan_output"

[ "${#rows[@]}" -eq 0 ] && pause_close "quicklook: nothing openable on screen"

if command -v fzf >/dev/null 2>&1; then
  selection="$(printf '%s\n' "${rows[@]}" | fzf \
    --prompt="pick ▸ " --reverse --cycle --height=100% \
    --delimiter=$'\t' --with-nth=2 \
    --header="$header")" || exit 0
  [ -z "$selection" ] && exit 0
else
  # No fzf: same degrade shape as recents-pane.sh - no interactive step,
  # takes row 1 (the clipboard token if it resolved, else the
  # highest-ranked on-screen candidate).
  selection="${rows[0]}"
fi

pick="${selection%%$'\t'*}"

export QUICKLOOK_TOKEN="$pick"
exec bash "$script_dir/preview-pane.sh"
