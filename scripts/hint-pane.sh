#!/usr/bin/env bash
# Pane `hint-pane`: the native hint picker overlay (real TTY). Opened by the
# `hint` action (scripts/hint.sh), which has no TTY of its own.
#
# Lists every openable token in the ORIGIN pane (forwarded as
# QUICKLOOK_HINT_ORIGIN_PANE, captured before this overlay stole focus - see
# scripts/pick.sh) with a one-key hint label. Press the key and the token is
# handed to preview-pane.sh via QUICKLOOK_TOKEN and `exec`'d IN THIS SAME PANE,
# so it resolves + renders + records exactly like every other quicklook open.
# No fzf and no herdr-pluck: a single keypress opens, or Esc/q cancels.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
. "$script_dir/lib.sh"

load_config

# Wait for one explicit key, then close. Used for the empty and error states so
# the overlay never flash-closes on a stray buffered keystroke.
wait_close() {
  printf '%s\n\n(press any key to close)' "$*"
  read -rsn1 _ 2>/dev/null || sleep 2
  exit 0
}

origin="${QUICKLOOK_HINT_ORIGIN_PANE:-}"
clip="${QUICKLOOK_HINT_CLIP:-}"

# Ranked token list. Row 0 is the clipboard token when it resolves (so the
# easiest hint opens what you just copied); the rest are the on-screen
# candidates with the clipboard token deduped out.
tokens=()
labels=()

if [ -n "$clip" ] && resolve_any_token "$clip" >/dev/null 2>&1; then
  tokens+=("$clip")
  labels+=("clipboard  $clip")
fi

while IFS=$'\t' read -r raw kind line_no; do
  [ -n "$raw" ] || continue
  [ "${#tokens[@]}" -gt 0 ] && [ "$raw" = "${tokens[0]}" ] && [ "${labels[0]}" = "clipboard  $raw" ] && continue
  tokens+=("$raw")
  labels+=("$(printf '%-5s L%-4s %s' "$kind" "$line_no" "$raw")")
  [ "${#tokens[@]}" -ge "${#QUICKLOOK_HINT_KEYS}" ] && break
done < <(pick_acquire "$origin")

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
while IFS= read -rsn1 key; do
  case "$key" in
    $'\e' | q | Q) exit 0 ;;
    '') continue ;;
    *)
      idx="$(hint_index_for_key "$key" 2>/dev/null)" || { continue; }
      [ "$idx" -lt "${#tokens[@]}" ] || continue
      export QUICKLOOK_TOKEN="${tokens[$idx]}"
      exec bash "$script_dir/preview-pane.sh"
      ;;
  esac
done
