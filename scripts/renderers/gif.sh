# shellcheck shell=bash
# gif.sh: animated-gif render-registry renderer (v0.4 SG-04). Draws `.gif`
# via `chafa --animate`; falls back to a first-frame STILL (the same ANSI
# symbols base path image.sh uses) when `--animate` is unavailable or fails.
# See the render-registry contract at the top of lib.sh.

# match_render_gif <path>: extension gate (.gif) PLUS a real
# `file --mime-type` check (declines a non-gif file renamed .gif - the
# negative control this sub-goal's quality bar calls out) PLUS chafa on PATH
# (absent -> decline -> fallback).
match_render_gif() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  command -v chafa >/dev/null 2>&1 || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  [ "$ext" = "gif" ] || return 1
  mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
  [ "$mime" = "image/gif" ]
}

# _GIF_ANIMATE_DURATION: chafa's own default duration for a single animated
# file is INFINITE (it loops until interrupted) - unbounded, so it would hang
# the pane forever. An explicit finite --duration bounds the animate path per
# this sub-goal's quality bar ("must never hang the pane"), while chafa still
# guarantees at least one full play-through of the frames. Overridable for a
# faster interactive tune without editing the script.
_GIF_ANIMATE_DURATION="${QUICKLOOK_GIF_ANIMATE_DURATION:-8}"

# render_gif <path> [line]: tries the bounded animate path first; a nonzero
# rc (chafa built without animate support, or it otherwise fails) falls back
# to a first-frame STILL via the same ANSI symbols call image.sh uses. `line`
# is accepted for signature parity (unused - no line to jump to on an
# image/gif). Pauses after drawing, matching the pane's pause-close idiom.
# No `o`/`d`/`e` overlay keys - same documented scope edge as image.sh.
render_gif() {
  local path="$1"
  # --animate takes an explicit =BOOL on chafa >= 1.18 (a bare --animate eats
  # the next argv and errors), and its --duration does NOT bound an animated
  # gif (measured: a 21s gif plays in full with --duration=2), so the bound
  # is enforced here with a wall-clock kill. The still fallback needs
  # --animate=off or chafa animates a multi-frame gif FOREVER even in
  # symbols format.
  chafa --animate=on -- "$path" 2>/dev/null &
  local _gif_pid=$! _gif_deadline=$((SECONDS + _GIF_ANIMATE_DURATION))
  while kill -0 "$_gif_pid" 2>/dev/null && [ "$SECONDS" -lt "$_gif_deadline" ]; do
    sleep 0.2
  done
  if kill -0 "$_gif_pid" 2>/dev/null; then
    kill "$_gif_pid" 2>/dev/null
    printf '\033[?25h\033[0m\n'
  fi
  if ! wait "$_gif_pid" 2>/dev/null; then
    chafa --animate=off --format symbols -- "$path" 2>/dev/null
  fi
  read -r -n1 -p 'press any key to close' _ 2>/dev/null || sleep 2
  return 0
}
