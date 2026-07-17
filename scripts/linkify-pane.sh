#!/usr/bin/env bash
# Pane `linkify-pane`: show a refreshable list of tokens from the origin pane.
# Each label carries an HTTPS-shaped OSC-8 URI consumed by this plugin's link
# handler, so herdr's existing Ctrl-click path can route arbitrary tokens.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

load_config
origin="${QUICKLOOK_LINKIFY_ORIGIN_PANE:-}"

render_links() {
  local scan header raw kind line_no uri count=0
  printf '\033[2J\033[H'
  printf 'Quicklook links · Ctrl+click to open · r refresh · q close\n\n'
  if [ -z "$origin" ]; then
    printf 'quicklook: origin pane is unavailable\n'
    return
  fi

  scan="$(pick_acquire "$origin")"
  header="$(pick_count_header <<<"$scan")"
  printf '%s\n\n' "$header"
  while IFS=$'\t' read -r raw kind line_no; do
    [ -n "$raw" ] || continue
    uri="$(quicklook_link_uri "$raw")" || continue
    printf '%-5s L%-4s ' "$kind" "$line_no"
    printf '\033]8;;%s\033\\%s\033]8;;\033\\\n' "$uri" "$raw"
    count=$((count + 1))
  done <<<"$scan"

  [ "$count" -gt 0 ] || printf 'quicklook: nothing openable on screen\n'
}

render_links
while IFS= read -rsn1 key; do
  case "$key" in
    q | Q | $'\e') exit 0 ;;
    r | R) render_links ;;
  esac
done
