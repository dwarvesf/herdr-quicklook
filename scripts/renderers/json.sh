# shellcheck shell=bash
# json.sh: render-registry stub (v0.4 roster pre-registration, SG-01).
# Declines every file until a later Wave-2/3 sub-goal fills in a real body;
# see the render-registry contract comment at the top of lib.sh. Wiring a
# real json renderer is a single-file edit to THIS file only - RENDER_KINDS,
# render_any, the sourcing glob, and preview-pane.sh stay untouched.

match_render_json() {
  return 1
}

render_json() {
  # unreachable: match_render_json always declines.
  return 1
}
