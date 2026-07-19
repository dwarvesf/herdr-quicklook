# shellcheck shell=bash
# markdown.sh: the markdown render-registry renderer (v0.4, SG-03). Parity
# target: herdr-file-viewer's own markdown support (a bare extension check +
# glow). See the render-registry contract comment at the top of lib.sh.

# match_render_markdown <path>: owns `.md`/`.markdown` files, but only when
# `glow` is on PATH (degrade is decided here, not mid-render - see the
# contract comment) AND file(1) reports a text encoding, not binary. The
# encoding check is what keeps a binary-garbage file wearing a `.md`
# extension from being handed to glow - extension alone is not enough of a
# type check (a markdown file IS text; glow itself has no binary guard).
match_render_markdown() {
  local path="$1" ext enc
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    md | markdown) ;;
    *) return 1 ;;
  esac
  command -v glow >/dev/null 2>&1 || return 1
  enc="$(file -b --mime-encoding -- "$path" 2>/dev/null)"
  [ "$enc" != "binary" ] && [ -n "$enc" ]
}

# render_markdown <path> [line]: pages `glow`'s rendered output through
# render_command_in_pager (glow -> less -R), same shape as every other
# formatter-piped renderer. `line` is accepted for signature parity with
# every other render_<kind> but unused - glow has no line-jump, so a
# best-effort render (not an error) is the contract here.
render_markdown() {
  local target="$1"
  render_command_in_pager glow -s auto -- "$target"
}
