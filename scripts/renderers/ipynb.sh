# shellcheck shell=bash
# ipynb.sh: Jupyter-notebook render-registry renderer (v0.4 SG-07, P3 pack).
# Converts the notebook to markdown via `pandoc -f ipynb` (pandoc's own ipynb
# reader - the tool README.md's Prerequisites table already commits `.ipynb`
# to, alongside `glow` for the P1 markdown row: no new undeclared dependency),
# strips pandoc's `::: {.cell ...}` / `:::` div-fence wrapper lines (goldmark,
# what `glow` renders with, does not understand pandoc-native fenced divs -
# left in, they would show up as literal `:::` noise around every cell), then
# feeds the result to `render_markdown` (SG-03) - reuse BY CALLING, never a
# duplicated glow/pager invocation. See the render-registry contract at the
# top of lib.sh.

# match_render_ipynb <path>: extension gate (.ipynb) PLUS pandoc AND glow on
# PATH (both required - render_ipynb always ends in a call to render_markdown,
# so glow's presence must be decided HERE, not mid-render, same as
# match_render_markdown's own gate) PLUS a text-encoding check (a .ipynb is
# JSON, i.e. text - `file --mime-encoding` reporting "binary" is the
# negative-control signal that this is garbage wearing a .ipynb extension, not
# a real notebook; declining here lets it fall through to `text`, which
# declines the same binary file for the same reason, landing it on
# `fallback` - exactly the "binary-garbage -> fallback" quality bar). A
# syntactically-broken-but-textual .ipynb (invalid JSON, valid UTF-8) still
# matches; pandoc's own parse failure is handled as a graceful in-pane message
# by render_ipynb below, never a crash.
match_render_ipynb() {
  local path="$1" ext enc
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  [ "$ext" = "ipynb" ] || return 1
  command -v pandoc >/dev/null 2>&1 || return 1
  command -v glow >/dev/null 2>&1 || return 1
  enc="$(file -b --mime-encoding -- "$path" 2>/dev/null)"
  [ "$enc" != "binary" ] && [ -n "$enc" ]
}

# render_ipynb <path> [line]: extracts to a `mktemp` markdown file (the
# office-conversion safety rule - office.sh's own temp files follow the same
# pattern - applies here too even though ipynb isn't "office"), a failed or
# empty conversion becomes a short in-pager notice instead of a blank/garbled
# render, then hands the file to `render_markdown` and returns ITS exit
# status. The temp file is removed after render_markdown returns (it pages
# synchronously - `render_command_in_pager` blocks on `less`, so control is
# back here before cleanup, never a dangling temp file). `line` is accepted
# for render_<kind> signature parity but unused, same as markdown.sh.
#
# The pandoc|sed pipeline runs INLINE in this function body (not behind a
# helper function) so `${PIPESTATUS[0]}` reads pandoc's real exit status -
# bash does not propagate PIPESTATUS across a function-call boundary, so a
# `_helper "$path" >"$tmp"; rc=${PIPESTATUS[0]}` shape would silently read 0
# every time (verified live; see DECISIONS.md).
render_ipynb() {
  local path="$1" tmp rc
  tmp="$(mktemp "${TMPDIR:-/tmp}/herdr-quicklook-ipynb.XXXXXX.md" 2>/dev/null)" || {
    render_fallback "$path"
    return $?
  }
  pandoc -f ipynb -t markdown -- "$path" 2>/dev/null | sed -E '/^:::/d' >"$tmp"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ] || [ ! -s "$tmp" ]; then
    printf 'quicklook: pandoc could not convert this notebook\n  path: %s\n' "$path" >"$tmp"
  fi
  render_markdown "$tmp"
  rc=$?
  rm -f -- "$tmp"
  return $rc
}
