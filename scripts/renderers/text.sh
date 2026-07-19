# shellcheck shell=bash
# text.sh: the reference render-registry renderer (v0.4, SG-01). This is the
# preview pane's original "render a local file" behavior - less driving the
# real FILE (not a bat pipe), so less keeps the filename and its `visual`
# command works: `o` (or `v`) escalates to the herdr-file-viewer pane via
# scripts/escalate.sh. bat becomes the LESSOPEN preprocessor for syntax
# highlighting; without bat, plain `less -N`. Moved here VERBATIM from
# preview-pane.sh's old RESOLVED_MODE=file tail - byte-for-byte behavior
# parity (o/d/e overlay keys via lesskey, +LINE jump, bat highlighting, the
# no-bat fallback). See the render-registry contract comment at the top of
# lib.sh.

# match_render_text <path>: this renderer owns anything file(1) reports as a
# text encoding (utf-8, us-ascii, iso-8859-1, ...); "binary" (and an
# unreadable/missing path) declines, leaving the always-0 `fallback`
# renderer as the catch-all (RENDER_KINDS keeps `text` second-to-last, see
# lib.sh).
match_render_text() {
  local path="$1" enc
  [ -f "$path" ] || return 1
  enc="$(file -b --mime-encoding -- "$path" 2>/dev/null)"
  [ "$enc" != "binary" ] && [ -n "$enc" ]
}

render_text() {
  local target="$1" line="${2:-}"
  local lesskey_args=()
  [ -f "$LIB_DIR/../lesskey" ] && lesskey_args=(--lesskey-src="$LIB_DIR/../lesskey")

  export VISUAL="$LIB_DIR/escalate.sh"
  # Read by the lesskey `e` pshell binding (escalate-editor.sh); see lesskey.
  export QUICKLOOK_EDITOR_SCRIPT="$LIB_DIR/escalate-editor.sh"
  if command -v bat >/dev/null 2>&1; then
    export LESSOPEN='|bat --color=always --style=numbers,header %s'
    exec less -R "${lesskey_args[@]}" ${line:++$line} "$target"
  fi
  exec less -N "${lesskey_args[@]}" ${line:++$line} "$target"
}
