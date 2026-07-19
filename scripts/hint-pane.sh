#!/usr/bin/env bash
# Pane `hint-pane`: the native hint picker overlay (real TTY). Opened by the
# `hint` action (scripts/hint.sh), which already read the origin pane and wrote
# two files: the ANSI-stripped visible snapshot ($QUICKLOOK_HINT_SNAP_FILE) and
# the ordered token list ($QUICKLOOK_HINT_TOKENS_FILE, `raw<TAB>line<TAB>label`).
#
# Pluck-style render: the snapshot is re-printed verbatim, and each openable
# token gets its hint LETTER overlaid on the token's first character (inverse
# video), the rest of the token underlined - columns never shift, so the user
# keeps the full context of the screen they were just reading. Every hinted
# token is also an OSC-8 sentinel link, so Ctrl+click opens the same way (the
# PR #22 linkify transport). A token the scanner saw but whose text cannot be
# re-found on its snapshot line falls into a short list under the snapshot.
#
# This overlay makes NO herdr RPC on purpose: a server RPC from a
# server-spawned overlay pane deadlocks (see hint.sh). Keys read from
# /dev/tty, not stdin: an overlay pane's stdin is not the interactive
# terminal. A hint keypress hands the chosen raw token to preview-pane.sh via
# QUICKLOOK_TOKEN, exec'd IN THIS SAME PANE. Esc/q cancels.
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
  [ -n "$tokens_file" ] && rm -f "$tokens_file" 2>/dev/null
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

tokens=()
lines_of=()
labels=()
if [ -n "$tokens_file" ] && [ -f "$tokens_file" ]; then
  while IFS=$'\t' read -r raw line_no label; do
    [ -n "$raw" ] || continue
    tokens+=("$raw")
    lines_of+=("$line_no")
    labels+=("$label")
    [ "${#tokens[@]}" -ge "${#QUICKLOOK_HINT_KEYS}" ] && break
  done <"$tokens_file"
fi

[ "${#tokens[@]}" -eq 0 ] && wait_close "quicklook: nothing openable on screen"

# ANSI pieces. The hint letter replaces the token's FIRST character (inverse
# video, bold); the remainder of the token is underlined. Both sit inside one
# OSC-8 hyperlink region, so column alignment is untouched and Ctrl+click
# works on the whole token.
H_KEY=$'\033[1;7m'
H_TOK=$'\033[4m'
H_OFF=$'\033[0m'
osc8() { printf '\033]8;;%s\033\\' "$1"; }
osc8_off() { printf '\033]8;;\033\\'; }

# styled_token <idx> -> the in-place replacement for tokens[idx]'s own text.
styled_token() {
  local i="$1" key tok uri
  key="$(hint_key_for_index "$i")"
  tok="${tokens[$i]}"
  if uri="$(quicklook_link_uri "$tok")"; then osc8 "$uri"; fi
  printf '%s%s%s' "$H_KEY" "$key" "$H_OFF"
  [ "${#tok}" -gt 1 ] && printf '%s%s%s' "$H_TOK" "${tok:1}" "$H_OFF"
  if [ -n "${uri:-}" ]; then osc8_off; fi
}

render() {
  printf '\033[2J\033[H'
  printf '%squicklook%s hint: type a letter or Ctrl+click to open · Esc/q cancel\n' "$H_KEY" "$H_OFF"

  local -a extras=()
  local i=0 ln=0 line pre tok

  # Clipboard row (line-no empty) always sits above the snapshot: it may not
  # be on screen at all, but it is the highest-priority pick.
  while [ "$i" -lt "${#tokens[@]}" ]; do
    if [ -z "${lines_of[$i]}" ]; then
      printf '  %s  %s\n' "$(styled_token "$i")" "${labels[$i]}"
    fi
    i=$((i + 1))
  done
  printf '\n'

  # Snapshot lines with in-place overlays. For each line, splice every token
  # the scanner pinned to it, rightmost-first so earlier byte offsets stay
  # valid while the line is rebuilt.
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln + 1))
    local -a here=()
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
    if [ "${#here[@]}" -gt 0 ]; then
      # Rightmost-first, and skip a token whose region overlaps one already
      # spliced (offsets into the original line would land inside the other
      # token's inserted escapes and garble the row); it stays pickable from
      # the extras list instead.
      local entry pos idx prev_start
      prev_start=99999
      while IFS= read -r entry; do
        pos="${entry%% *}"; pos=$((10#$pos))
        idx="${entry##* }"
        tok="${tokens[$idx]}"
        if [ $((pos + ${#tok})) -gt "$prev_start" ]; then
          extras+=("$idx")
          continue
        fi
        line="${line:0:$pos}$(styled_token "$idx")${line:$((pos + ${#tok}))}"
        prev_start=$pos
      done < <(printf '%s\n' "${here[@]}" | sort -r)
    fi
    printf '%s\n' "$line"
  done <"$snap_file"

  # Tokens whose text no longer matches their snapshot line (wrapped, trimmed
  # by the scanner, or scrolled) still get pickable rows at the bottom.
  if [ "${#extras[@]}" -gt 0 ]; then
    printf '\n'
    for i in "${extras[@]}"; do
      printf '  %s  %s\n' "$(styled_token "$i")" "${labels[$i]}"
    done
  fi
}

if [ -n "$snap_file" ] && [ -s "$snap_file" ]; then
  render
else
  # No snapshot (agent push, tests): plain labeled list, same keys.
  printf '\033[2J\033[H'
  printf 'quicklook hint: type a letter or Ctrl+click to open · Esc/q cancel\n\n'
  i=0
  while [ "$i" -lt "${#tokens[@]}" ]; do
    printf '  %s  %s\n' "$(styled_token "$i")" "${labels[$i]}"
    i=$((i + 1))
  done
fi

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
