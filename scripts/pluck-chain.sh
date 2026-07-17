#!/usr/bin/env bash
# Action `pluck-chain`: show herdr-pluck's hint overlay, then open the picked
# token immediately in the preview overlay - no separate keypress to consume
# it. herdr-pluck is a pure enhancement with NO hard dependency: when it is
# not installed, or when triggering it fails, this reroutes to the native
# `pick` action (scan-the-pane, pick-anywhere) instead of the plain clipboard
# flow, so the same key always lands on a working pick-anywhere experience.
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
# "nothing picked"), and for why the reroute below targets the `pick` PLUGIN
# ACTION id rather than execing scripts/pick.sh directly.
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

# The one reroute arm: invoked both when herdr-pluck is absent and when
# triggering it fails. Targets the `pick` action by ID (not
# `scripts/pick.sh` by path) so this script never needs to know where that
# script lives or whether it exists yet.
reroute_to_pick() {
  exec "$herdr_bin" plugin action invoke pick --plugin herdr-quicklook
}

# Soft dependency: without herdr-pluck there is no hint overlay to chain
# from, so this reroutes to the native pick-anywhere overlay instead of doing
# nothing (same idiom as open-in-viewer.sh's herdr-file-viewer gate, which
# used to degrade to the plain clipboard flow here too).
if ! "$herdr_bin" plugin action list --plugin rmarganti.herdr-pluck >/dev/null 2>&1; then
  notify "herdr-pluck not installed; opening the pick-anywhere overlay"
  reroute_to_pick
fi

before="$(clip_read_now)"

if ! "$herdr_bin" plugin action invoke pluck --plugin rmarganti.herdr-pluck >/dev/null 2>&1; then
  notify "herdr-pluck failed to open; opening the pick-anywhere overlay"
  reroute_to_pick
fi

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
