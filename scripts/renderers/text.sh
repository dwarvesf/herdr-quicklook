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
  # %f is less's own filename escape: the footer carries the name that the
  # dropped bat header used to show, without occupying a line.
  pager_prompt_args '%f · '

  export VISUAL="$LIB_DIR/escalate.sh"
  # Read by the lesskey `e` pshell binding (escalate-editor.sh); see lesskey.
  export QUICKLOOK_EDITOR_SCRIPT="$LIB_DIR/escalate-editor.sh"
  if command -v bat >/dev/null 2>&1; then
    # Display parity with herdr-file-viewer, which runs bat with NO theme
    # flag so the user's own bat config decides (Han's pins TwoDark with a
    # "both panes read this" note). Pinning a theme here would override
    # that config and un-sync the panes, so QUICKLOOK_BAT_THEME adds a
    # --theme flag ONLY when explicitly set.
    #
    # style=numbers, NOT numbers,header: `less +N` counts lines in the
    # LESSOPEN-FILTERED stream, so bat's one-line "File: ..." header shifts
    # every `path:N` jump down by one (measured: a 5-line file renders as 6
    # rows with header). The viewer itself runs plain `--style=numbers`, so
    # dropping the header is also the real parity. The filename is carried
    # in the pager footer instead (%f), where it costs no lines.
    LESSOPEN="|bat --color=always $(_bat_theme_flag)--style=numbers %s"
    export LESSOPEN
    exec less -R "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${line:++$line} "$target"
  fi
  exec less -N "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${line:++$line} "$target"
}
