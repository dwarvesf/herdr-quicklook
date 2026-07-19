# shellcheck shell=bash
# svg.sh: svg render-registry renderer (v0.4 SG-06/P2). Converts to a PNG
# via `rsvg-convert`, then draws it through image.sh's render_image (SG-04)
# - reusing the SAME chafa invocation image.sh already uses rather than a
# second copy, per this sub-goal's scope edge. See the render-registry
# contract at the top of lib.sh.

# match_render_svg <path>: owns `.svg` files, but only when BOTH
# `rsvg-convert` and `chafa` are on PATH (degrade is decided here, not
# mid-render - see the contract comment) AND file(1) actually reports the
# svg mime type, not just a matching extension - the negative control this
# sub-goal's quality bar calls out (a binary-garbage/renamed file never
# reaches rsvg-convert). Note: an svg is XML TEXT, so when this renderer
# declines on a genuinely absent tool, the registry cascade (RENDER_KINDS
# in lib.sh) lands the file on the `text` renderer, not `fallback` - the
# same precedent markdown.sh's glow-absent degrade already established for
# textual content (see its own bats file); only a non-text kind's
# tool-absent decline naturally reaches `fallback` (pdf.sh, archive.sh).
match_render_svg() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  [ "$ext" = "svg" ] || return 1
  command -v rsvg-convert >/dev/null 2>&1 || return 1
  command -v chafa >/dev/null 2>&1 || return 1
  mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
  [ "$mime" = "image/svg+xml" ]
}

# render_svg <path> [line]: rsvg-convert -> a temp PNG -> render_image (the
# SAME chafa invocation image.sh already uses, never re-implemented here).
# A conversion failure (a corrupt svg that still passed the mime check)
# degrades to render_fallback rather than crashing or drawing a blank
# frame. `line` is accepted for render_<kind> signature parity but unused -
# no line to jump to on an inline image. The temp PNG is always removed,
# on every exit path.
render_svg() {
  local path="$1" tmp_png rc
  tmp_png="$(mktemp "${TMPDIR:-/tmp}/herdr-quicklook-svg-XXXXXX.png" 2>/dev/null)" || tmp_png=""
  if [ -z "$tmp_png" ] || ! rsvg-convert -o "$tmp_png" -- "$path" 2>/dev/null; then
    [ -n "$tmp_png" ] && rm -f -- "$tmp_png"
    render_fallback "$path"
    return $?
  fi
  render_image "$tmp_png"
  rc=$?
  rm -f -- "$tmp_png"
  return "$rc"
}
