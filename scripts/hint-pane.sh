#!/usr/bin/env bash
# Pane `hint-pane`: the native hint picker overlay (real TTY). Opened by the
# `hint` action (scripts/hint.sh), which wrote the ANSI-stripped visible
# snapshot ($QUICKLOOK_HINT_SNAP_FILE) and left a BACKGROUND scan running that
# will drop the token list at $QUICKLOOK_HINT_TOKENS_FILE (atomic mv;
# existence = scan done; line: `raw<TAB>line<TAB>uri<TAB>label`).
#
# Latency contract: render the raw snapshot the instant this pane opens, poll
# for the token list (Esc/q abort any time), then overlay the hints. Render is
# fork-free on purpose (keys via substring, URIs precomputed by the action):
# the first paint and the hint paint are both single printf writes.
#
# Pluck-style render: the snapshot is re-printed dimmed, and each openable
# token gets its hint LETTER overlaid on the token's first character (black
# on bright yellow), the rest of the token bright yellow - columns never
# shift, so the user keeps the full context of the screen they were reading. Every hinted
# token is also an OSC-8 sentinel link, so Ctrl+click opens the same way. A
# token whose text cannot be re-found on its snapshot line falls into a short
# list under the snapshot.
#
# This overlay makes NO herdr RPC (a server RPC from a server-spawned overlay
# pane deadlocks). Keys read from /dev/tty, not stdin. A hint keypress hands
# the chosen raw token to preview-pane.sh via QUICKLOOK_TOKEN, exec'd IN THIS
# SAME PANE. Esc/q cancels.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
. "$script_dir/lib.sh"

load_config

# Enter the origin repo so the open step's resolve() sees it as $PWD.
if [ -n "${QUICKLOOK_HINT_CWD:-}" ] && [ -d "$QUICKLOOK_HINT_CWD" ]; then
  cd "$QUICKLOOK_HINT_CWD" || true
fi

tokens_file="${QUICKLOOK_HINT_TOKENS_FILE:-}"
snap_file="${QUICKLOOK_HINT_SNAP_FILE:-}"
cleanup() {
  printf '\033[?25h\033[?7h'
  [ -n "$tokens_file" ] && rm -f "$tokens_file" "$tokens_file.part" 2>/dev/null
  [ -n "$snap_file" ] && rm -f "$snap_file" 2>/dev/null
}

tty_in=/dev/tty
[ -r "$tty_in" ] || tty_in=/dev/stdin

wait_close() {
  printf '%s\n\n(press any key to close)' "$*"
  read -rsn1 _ <"$tty_in" 2>/dev/null || sleep 3
  cleanup
  exit 0
}

# Pluck's scheme, Han's palette: the snapshot dims to dark grey so hints pop,
# the token text goes bright yellow, and the hint badge is bold black on
# bright yellow #fffd01 (truecolor: the palette "yellow" renders orange under
# one-dark). Every style opens with a reset so it never inherits the dim.
DIM=$'\033[2;90m'
RESET=$'\033[0m'
H_KEY=$'\033[0;1;30;48;2;255;253;1m'
H_TOK=$'\033[0;38;2;255;253;1m'
H_OFF=$'\033[0m'
OSC8_OFF=$'\033]8;;\033\\'

NL=$'\n'
# HOME + hide-cursor for the first paint; repaints overwrite in place and
# clear only what is below (ESC[J), never the whole screen - a full ESC[2J
# between paints is the blank-frame flicker pluck does not have. Autowrap is
# OFF while the overlay lives: a snapshot line longer than this pane (the
# overlay border eats 2 columns) must truncate, not reflow - reflow grows the
# row count past the pane height, the terminal scrolls, and the next ESC[H
# paints over a shifted screen (the merged/duplicated-lines corruption).
HOME=$'\033[H'
EOD=$'\033[J'
CURSOR_HIDE=$'\033[?25l'
WRAP_OFF=$'\033[?7l'

# Snapshot lines + the overlay's real height. Keep the BOTTOM rows when the
# snapshot is taller than this pane (the border eats rows vs the origin):
# the bottom is where the user was working.
snap_lines=()
if [ -n "$snap_file" ] && [ -f "$snap_file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do snap_lines+=("$line"); done <"$snap_file"
fi
total=${#snap_lines[@]}
rows="$(stty size <"$tty_in" 2>/dev/null | awk '{print $1}')"
case "$rows" in '' | *[!0-9]*) rows=0 ;; esac
offset=0
[ "$rows" -gt 0 ] && [ "$total" -gt "$rows" ] && offset=$((total - rows))

# First paint: the raw snapshot, instantly, one write, dimmed from the start
# so the mode-switch is visible without any header line. No newline after the
# last row (that alone scrolls a full pane), %s on purpose: snapshot text may
# contain literal \n / \t sequences that %b would corrupt.
frame="${CURSOR_HIDE}${WRAP_OFF}${HOME}"
i="$offset"
while [ "$i" -lt "$total" ]; do
  frame+="${DIM}${snap_lines[$i]}${RESET}"
  [ $((i + 1)) -lt "$total" ] && frame+="$NL"
  i=$((i + 1))
done
frame+="$EOD"
printf '%s' "$frame"

# Wait for the background scan (existence of tokens_file = done), polling the
# tty so Esc/q aborts mid-scan. Cap ~5s.
waited=0
while [ ! -f "${tokens_file:-/nonexistent}" ]; do
  if read -t 0.1 -rsn1 key <"$tty_in" 2>/dev/null; then
    case "$key" in $'\e' | q | Q) cleanup; exit 0 ;; esac
  fi
  waited=$((waited + 1))
  [ "$waited" -ge 50 ] && wait_close "quicklook: scan timed out"
done

tokens=()
lines_of=()
uris=()
labels=()
while IFS=$'\t' read -r raw line_no uri label; do
  [ -n "$raw" ] || continue
  tokens+=("$raw")
  lines_of+=("$line_no")
  uris+=("$uri")
  labels+=("$label")
  [ "${#tokens[@]}" -ge "${#QUICKLOOK_HINT_KEYS}" ] && break
done <"$tokens_file"

[ "${#tokens[@]}" -eq 0 ] && wait_close "quicklook: nothing openable on screen"

# styled_for <idx> -> $STYLED: the in-place replacement for tokens[idx]'s own
# text. Fork-free: key by substring, URI precomputed by the action.
styled_for() {
  local i="$1" key tok uri
  key="${QUICKLOOK_HINT_KEYS:$i:1}"
  tok="${tokens[$i]}"
  uri="${uris[$i]}"
  STYLED=""
  [ -n "$uri" ] && STYLED+=$'\033]8;;'"$uri"$'\033\\'
  STYLED+="${H_KEY}${key}${H_OFF}"
  [ "${#tok}" -gt 1 ] && STYLED+="${H_TOK}${tok:1}${H_OFF}"
  [ -n "$uri" ] && STYLED+="$OSC8_OFF"
}

# Second paint: snapshot with in-place hint overlays, one write, overwriting
# the first paint in place (no clear, no flicker).
frame="${HOME}"
extras=()

# Rows with no line-no (not re-locatable on screen) join the extras list.
i=0
while [ "$i" -lt "${#tokens[@]}" ]; do
  if [ -z "${lines_of[$i]}" ]; then
    extras+=("$i")
  fi
  i=$((i + 1))
done

# Tokens pinned to a line the height-clamp cut still get extras rows.
i=0
while [ "$i" -lt "${#tokens[@]}" ]; do
  ln="${lines_of[$i]}"
  if [ -n "$ln" ] && [ "$ln" -le "$offset" ] 2>/dev/null; then
    extras+=("$i")
  fi
  i=$((i + 1))
done

lidx="$offset"
while [ "$lidx" -lt "$total" ]; do
  line="${snap_lines[$lidx]}"
  ln=$((lidx + 1))
  here=()
  i=0
  while [ "$i" -lt "${#tokens[@]}" ]; do
    if [ "${lines_of[$i]}" = "$ln" ]; then
      tok="${tokens[$i]}"
      pre="${line%%"$tok"*}"
      if [ "$pre" = "$line" ]; then
        extras+=("$i")
      else
        here+=("$(printf '%08d %s' "${#pre}" "$i")")
      fi
    fi
    i=$((i + 1))
  done
  if [ "${#here[@]}" -gt 1 ]; then
    # Rightmost-first so earlier byte offsets stay valid while the line is
    # rebuilt; skip a token whose region overlaps one already spliced (its
    # offsets would land inside the other token's escapes) - it stays
    # pickable from the extras list instead.
    sorted="$(printf '%s\n' "${here[@]}" | sort -r)"
    here=()
    while IFS= read -r entry; do here+=("$entry"); done <<<"$sorted"
  fi
  prev_start=99999
  for entry in "${here[@]:-}"; do
    [ -n "$entry" ] || continue
    pos="${entry%% *}"; pos=$((10#$pos))
    idx="${entry##* }"
    tok="${tokens[$idx]}"
    if [ $((pos + ${#tok})) -gt "$prev_start" ]; then
      extras+=("$idx")
      continue
    fi
    styled_for "$idx"
    line="${line:0:$pos}${STYLED}${DIM}${line:$((pos + ${#tok}))}"
    prev_start=$pos
  done
  frame+="${DIM}${line}${RESET}"
  [ $((lidx + 1)) -lt "$total" ] && frame+="$NL"
  lidx=$((lidx + 1))
done

# Tokens whose text no longer matches their snapshot line (wrapped, trimmed
# by the scanner, or the off-screen clipboard shape) still get pickable rows.
if [ "${#extras[@]}" -gt 0 ]; then
  for i in "${extras[@]}"; do
    styled_for "$i"
    frame+="${NL}  ${STYLED}  ${DIM}${labels[$i]}${RESET}"
  done
fi
frame+="$EOD"

printf '%s' "$frame"

while IFS= read -rsn1 key <"$tty_in"; do
  case "$key" in
    $'\e' | q | Q) cleanup; exit 0 ;;
    '') continue ;;
    *)
      idx="$(hint_index_for_key "$key" 2>/dev/null)" || continue
      [ "$idx" -lt "${#tokens[@]}" ] || continue
      cleanup
      # Open by TYPE: a directory goes to the real navigable file-viewer
      # (open-in-viewer's viewer arm can drive another pane over the socket);
      # everything else - files to the popup pager, URLs to the browser -
      # rides preview-pane's existing dispatch. QUICKLOOK_KEEP_CWD pins
      # open-in-viewer to this pane's cwd (the origin repo) instead of the
      # overlay's own pane cwd.
      if resolve_any_token "${tokens[$idx]}" 2>/dev/null && [ "${RESOLVED_MODE:-}" = "viewer" ]; then
        export QUICKLOOK_KEEP_CWD=1
        exec bash "$script_dir/open-in-viewer.sh" "${tokens[$idx]}"
      fi
      export QUICKLOOK_TOKEN="${tokens[$idx]}"
      exec bash "$script_dir/preview-pane.sh"
      ;;
  esac
done
cleanup
