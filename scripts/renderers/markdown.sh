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
# _markdown_glow_style -> the value for glow's -s flag, on stdout.
# Precedence: QUICKLOOK_GLOW_STYLE (a glow style name or a JSON style file)
# > herdr-file-viewer's bundled palette when that plugin is installed (so
# the preview overlay and the viewer render markdown identically) > auto.
# The viewer ships its palette at assets/markdown-style.json and treats it
# as a trusted glow argument; pointing our glow at the same file is the
# whole "pick up the viewer's highlighting" feature.
_markdown_glow_style() {
  if [ -n "${QUICKLOOK_GLOW_STYLE:-}" ]; then
    printf '%s' "$QUICKLOOK_GLOW_STYLE"
    return 0
  fi
  # augment_roots (load_config) already captured the viewer root from its
  # own plugin-list fork; querying again here would pay the same herdr+jq
  # cost twice per render. The query below is only the fallback for callers
  # that never ran load_config (tests sourcing lib.sh directly).
  local vroot="${QUICKLOOK_VIEWER_ROOT:-}"
  if [ -z "$vroot" ]; then
    # shellcheck disable=SC2154  # herdr_bin is set by lib.sh before this file is sourced
    vroot="$("$herdr_bin" plugin list --json 2>/dev/null \
      | jq -r '.result.plugins[] | select(.plugin_id == "herdr-file-viewer") | .plugin_root // empty' 2>/dev/null)"
  fi
  if [ -n "$vroot" ] && [ -f "$vroot/assets/markdown-style.json" ]; then
    printf '%s' "$vroot/assets/markdown-style.json"
    return 0
  fi
  printf 'auto'
}

render_markdown() {
  local target="$1" cols
  # glow's stdout is a PIPE inside render_command_in_pager, so its auto
  # width is a hard 80 no matter how wide the pane is; source lines wider
  # than 80 then double-wrap into ragged orphan fragments. stdout here is
  # still the pane's TTY, so measure it and pass the width explicitly.
  cols="$(tput cols 2>/dev/null)" || cols=80
  render_command_in_pager glow -s "$(_markdown_glow_style)" -w "${cols:-80}" -- "$target"
}
