# shellcheck shell=bash
# image.sh: still-image render-registry renderer (v0.4 SG-04). Draws PNG/JPG/
# JPEG/WEBP/BMP inline via chafa in ANSI symbols mode - the guaranteed BASE
# PATH that works in any pane/terminal (see the render-registry contract at
# the top of lib.sh). kitty-graphics passthrough is an ENHANCEMENT only: when
# the terminal signals kitty-protocol support, chafa is invoked WITHOUT an
# explicit --format so it auto-detects and upgrades the render; chafa's own
# auto mode still falls back to a text format on a bad guess, so a false
# positive here only costs a slightly worse render, never a crash - safe and
# reversible, which is the bar this sub-goal's feasibility gate set.

# match_render_image <path>: extension gate (png/jpg/jpeg/webp/bmp) PLUS a
# real `file --mime-type` check (the extension alone would let a renamed
# garbage/text file through - the negative control this sub-goal's quality
# bar calls out) PLUS chafa on PATH (absent -> decline -> fallback, an image
# is never worth a raw-byte dump).
match_render_image() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  command -v chafa >/dev/null 2>&1 || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    png | jpg | jpeg | webp | bmp) ;;
    *) return 1 ;;
  esac
  mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
  case "$mime" in
    image/*) ;;
    *) return 1 ;;
  esac
}

# _image_terminal_supports_kitty: the only signals trusted for the kitty-
# passthrough enhancement - kitty itself ($KITTY_WINDOW_ID) and $TERM ==
# xterm-kitty (kitty's own default TERM value). Anything else stays on the
# ANSI symbols base path; a missed positive here costs a worse render, never
# a crash, which is what makes the enhancement safe to feasibility-test.
_image_terminal_supports_kitty() {
  [ -n "${KITTY_WINDOW_ID:-}" ] && return 0
  [ "${TERM:-}" = "xterm-kitty" ]
}

# render_image <path> [line]: base path is an explicit `chafa --format
# symbols` (works in ANY terminal); the kitty-capable branch omits --format
# so chafa's own probe/auto-detect can pick kitty-graphics passthrough.
# `line` is accepted for render_<kind> signature parity (render_any always
# passes it) but unused - an inline image render has no line to jump to.
# Pauses after drawing (read/keypress) so the overlay does not instantly
# close, matching the pane's existing pause-close idiom (see fallback.sh).
# No `o`/`d`/`e` overlay keys here - there is no less session to bind them
# to; documented as a scope edge in the goal file, not a bug.
render_image() {
  local path="$1"
  if _image_terminal_supports_kitty; then
    chafa -- "$path" 2>/dev/null
  else
    chafa --format symbols -- "$path" 2>/dev/null
  fi
  read -r -n1 -p 'press any key to close' _ 2>/dev/null || sleep 2
  return 0
}
