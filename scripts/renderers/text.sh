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
  pager_prompt_args

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
    # style=numbers,header puts the FILENAME on top, where it belongs; the
    # footer stays keys-only.
    #
    # The header occupies rows in the LESSOPEN-filtered stream that `less
    # +N` counts, so a `path:N` jump must skip them. Its height is NOT a
    # constant: bat wraps the "File: ..." line, so a long path in a narrow
    # pane takes two rows where a short one takes one (measured both).
    # Measure it instead of guessing, with a one-line probe render, and
    # only when a jump was actually requested.
    LESSOPEN="|bat --color=always $(_bat_theme_flag)--style=numbers,header %s"
    export LESSOPEN
    local jump="$line" probe
    if [ -n "$jump" ]; then
      probe="$(bat --color=always --style=numbers,header --line-range 1:1 -- "$target" 2>/dev/null | wc -l | tr -d ' ')"
      case "$probe" in
        '' | *[!0-9]*) : ;;
        *) [ "$probe" -gt 1 ] && jump=$((jump + probe - 1)) ;;
      esac
    fi
    exec less -R "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${jump:++$jump} "$target"
  fi
  exec less -N "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${line:++$line} "$target"
}
