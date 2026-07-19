#!/usr/bin/env bash
# Pane `hint-pane`: the native hint picker overlay (real TTY). Opened by the
# `hint` action (scripts/hint.sh), which already scanned the origin pane and
# wrote the ordered "raw<TAB>label" list to $QUICKLOOK_HINT_TOKENS_FILE.
#
# This overlay makes NO herdr RPC on purpose: a server RPC from a server-spawned
# overlay pane deadlocks (see hint.sh). It only reads the token file, renders a
# one-key hint label per token, and on a keypress hands the chosen raw token to
# preview-pane.sh via QUICKLOOK_TOKEN, `exec`'d IN THIS SAME PANE, so it resolves
# + renders + records exactly like every other quicklook open. Esc/q cancels.
#
# Keys read from /dev/tty, not stdin: an overlay pane's stdin is not the
# interactive terminal (fzf-based panes read /dev/tty for the same reason).
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
cleanup() { [ -n "$tokens_file" ] && rm -f "$tokens_file" 2>/dev/null; }

tty_in=/dev/tty
[ -r "$tty_in" ] || tty_in=/dev/stdin

wait_close() {
  printf '%s\n\n(press any key to close)' "$*"
  read -rsn1 _ <"$tty_in" 2>/dev/null || sleep 3
  cleanup
  exit 0
}

tokens=()
labels=()
if [ -n "$tokens_file" ] && [ -f "$tokens_file" ]; then
  while IFS=$'\t' read -r raw label; do
    [ -n "$raw" ] || continue
    tokens+=("$raw")
    labels+=("$label")
    [ "${#tokens[@]}" -ge "${#QUICKLOOK_HINT_KEYS}" ] && break
  done <"$tokens_file"
fi

[ "${#tokens[@]}" -eq 0 ] && wait_close "quicklook: nothing openable on screen"

render() {
  printf '\033[2J\033[H'
  printf 'Quicklook hint · press a key to open · Esc/q cancel\n\n'
  local i=0 key
  while [ "$i" -lt "${#tokens[@]}" ]; do
    key="$(hint_key_for_index "$i")"
    printf '  [%s]  %s\n' "$key" "${labels[$i]}"
    i=$((i + 1))
  done
}

render
while IFS= read -rsn1 key <"$tty_in"; do
  case "$key" in
    $'\e' | q | Q) cleanup; exit 0 ;;
    '') continue ;;
    *)
      idx="$(hint_index_for_key "$key" 2>/dev/null)" || continue
      [ "$idx" -lt "${#tokens[@]}" ] || continue
      export QUICKLOOK_TOKEN="${tokens[$idx]}"
      cleanup
      exec bash "$script_dir/preview-pane.sh"
      ;;
  esac
done
cleanup
