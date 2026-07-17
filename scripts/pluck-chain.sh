#!/usr/bin/env bash
# Action `pluck-chain`: show herdr-pluck's hint overlay, then open the picked
# token immediately in the preview overlay - no separate keypress to consume
# it. Degrades to the plain clipboard flow (identical to the `preview`
# action) when herdr-pluck is not installed.
#
# herdr-pluck's ONLY output channel is the system clipboard (confirmed in its
# own README/source: pbcopy/wl-copy/xclip, no other IPC), and its `open`
# subcommand only launches a temporary picker tab and returns immediately -
# the actual pick happens asynchronously over there (a real TTY running
# `herdr-pluck pick`). So this script cannot block on pluck's own exit; it
# polls the clipboard for a change instead and forwards whatever lands there
# straight into open-preview.sh's existing QUICKLOOK_TOKEN channel. See
# DECISIONS.md for the "no clipboard hop" framing and the one disclosed edge
# case (re-picking a value already on the clipboard is indistinguishable from
# "nothing picked").
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
herdr_bin="${HERDR_BIN_PATH:-herdr}"

notify() {
  "$herdr_bin" notification show "quicklook" --body "$1" --sound none >/dev/null 2>&1
}

clip_read_now() {
  if command -v pbpaste >/dev/null 2>&1; then pbpaste
  elif command -v wl-paste >/dev/null 2>&1; then wl-paste --no-newline
  elif command -v xclip >/dev/null 2>&1; then xclip -o -selection clipboard
  fi 2>/dev/null
}

# Soft dependency: without herdr-pluck there is no hint overlay to chain
# from, so this degrades to the plain clipboard flow instead of doing
# nothing (same idiom as open-in-viewer.sh's herdr-file-viewer gate).
if ! "$herdr_bin" plugin action list --plugin rmarganti.herdr-pluck >/dev/null 2>&1; then
  notify "herdr-pluck not installed; opening the clipboard flow"
  exec bash "$script_dir/open-preview.sh"
fi

before="$(clip_read_now)"

"$herdr_bin" plugin action invoke pluck --plugin rmarganti.herdr-pluck >/dev/null 2>&1

# Poll for a clipboard change. Knobs are overridable for tests (fast, no real
# sleep) and for a slower human on a loaded machine (QUICKLOOK_PLUCK_TIMEOUT).
interval="${QUICKLOOK_PLUCK_POLL_INTERVAL:-0.15}"
timeout="${QUICKLOOK_PLUCK_TIMEOUT:-20}"
iterations="$(awk -v t="$timeout" -v i="$interval" 'BEGIN { if (i <= 0) i = 0.01; n = t / i; print (n == int(n)) ? n : int(n) + 1 }')"

picked=""
i=0
while [ "$i" -lt "$iterations" ]; do
  sleep "$interval"
  now="$(clip_read_now)"
  if [ "$now" != "$before" ]; then
    picked="$now"
    break
  fi
  i=$((i + 1))
done

if [ -z "$picked" ]; then
  notify "pluck: no selection"
  exit 0
fi

# Forward the picked token explicitly (the same --env QUICKLOOK_TOKEN channel
# open-preview.sh already uses for agent-pushed tokens), so the new preview
# pane doesn't need to re-read the clipboard itself.
exec bash "$script_dir/open-preview.sh" "$picked"
