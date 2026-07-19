# shellcheck shell=bash
# fallback.sh: the always-on catch-all render-registry renderer (v0.4, SG-01).
# Real body now (a minimal one), not a stub: an unknown/binary file must
# never dump raw bytes into the pane, even before any later Wave has a real
# renderer for it. match_render_fallback always matches; RENDER_KINDS keeps
# `fallback` last (see the render-registry contract comment at the top of
# lib.sh) so it only ever runs once every more-specific kind has declined.

match_render_fallback() {
  return 0
}

# render_fallback <path> [line]: a `file(1)` one-line type description plus
# an optional RENDER_HINTS-derived "you might want X" hint by extension -
# never the file's raw bytes. `line` is accepted (for signature parity with
# every other render_<kind>) but unused: a byte-safe type description has no
# concept of a line to jump to.
render_fallback() {
  local path="$1" desc hint ext
  desc="$(file -b -- "$path" 2>/dev/null)"
  [ -n "$desc" ] || desc="unknown file type"
  printf 'quicklook: no specific renderer for this file yet\n'
  printf '  path: %s\n' "$path"
  printf '  type: %s\n' "$desc"
  ext="${path##*.}"
  if [ "$ext" != "$path" ] && hint="$(render_hint_for_ext "$ext")" && [ -n "$hint" ]; then
    printf '  hint: consider %s\n' "$hint"
  fi
  read -r -n1 -p 'press any key to close' _ 2>/dev/null || sleep 2
  return 0
}
