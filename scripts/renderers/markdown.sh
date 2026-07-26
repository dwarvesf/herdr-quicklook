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
  # viewer_root (lib.sh) prefers the root augment_roots already captured, so
  # this costs no extra fork on the normal path.
  local vroot
  vroot="$(viewer_root || true)"
  if [ -n "$vroot" ] && [ -f "$vroot/assets/markdown-style.json" ]; then
    printf '%s' "$vroot/assets/markdown-style.json"
    return 0
  fi
  printf 'auto'
}

# glamour draws a table's header rule and its column separators, but has no
# per-row rule and no style key that turns one on (border_row / row_border /
# border / table_border are all ignored by glow 2.1.2), so multi-line rows
# run together , the readability complaint these two filters fix.
#
# _md_table_spacers (pre): inject a marker ROW between every pair of data
# rows, so glamour lays it out with the table's real column geometry.
# _md_table_rules (post): swap each rendered marker line for a copy of that
# table's own header rule, which glamour already drew at exactly the right
# width. Splitting it this way is what keeps the filter ANSI-safe , we never
# parse styled output, we replace whole lines and reuse a line glamour made.
MD_TABLE_MARK='⟦qlhr⟧'

_md_table_spacers() {
  awk -v mark="$MD_TABLE_MARK" '
    /^[ \t]*(```|~~~)/ { fence = !fence; print; next }
    fence { print; next }
    $0 !~ /^[ \t]*\|/ { intable = 0; print; next }
    # the |---|---| delimiter row opens the table and fixes its column count
    $0 ~ /^[ \t]*\|[ \t:|-]+\|[ \t]*$/ {
      intable = 1; seen = 0; pipes = gsub(/\|/, "|"); print; next
    }
    {
      if (intable && seen) {
        s = "|" mark
        for (i = 1; i < pipes; i++) s = s "|"
        print s
      }
      if (intable) seen = 1
      print
    }
  '
}

# `┼` only ever appears in glamour's header rule, so it is the cheapest
# byte-literal way to spot that line without decoding ANSI or multibyte
# content. h stores it; g replays it over the marker line. The match is on
# the marker's opening bracket alone, so a narrow first column that ellipses
# the marker's tail still gets swapped.
_md_table_rules() {
  sed -e '/┼/h' -e '/⟦/{ g; }'
}

_md_glow() {
  local target="$1" cols="$2" style
  style="$(_markdown_glow_style)"
  if [ "${QUICKLOOK_TABLE_RULES:-1}" = 0 ]; then
    glow -s "$style" -w "$cols" -- "$target"
    return
  fi
  _md_table_spacers <"$target" | glow -s "$style" -w "$cols" - | _md_table_rules
}

render_markdown() {
  local target="$1"
  # glow's stdout is a PIPE inside render_command_in_pager, so its auto
  # width is a hard 80 no matter how wide the pane is; source lines wider
  # than 80 then double-wrap into ragged orphan fragments, and tables get
  # squeezed into 80 columns of a much wider pane. pane_cols (lib.sh) reads
  # the true width off /dev/tty and already subtracts the pad_left gutter.
  render_command_in_pager _md_glow "$target" "$(pane_cols)"
}
