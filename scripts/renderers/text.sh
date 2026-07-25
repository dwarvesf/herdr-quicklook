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

# _fits_in_pane <file>: true when the file is shorter than the pane, i.e.
# when it would render bottom-anchored with blank rows above it.
_fits_in_pane() {
  local rows n
  rows="$(_pane_rows)"
  [ "$rows" -gt 1 ] || return 1
  n="$(wc -l < "$1" 2>/dev/null | tr -d ' ')" || return 1
  case "$n" in '' | *[!0-9]*) return 1 ;; esac
  [ "$n" -lt "$((rows - 1))" ]
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
    # style=numbers, no header: the object's name lives in the pager
    # FOOTER (pager_prompt_args prefixes it), which costs no content row,
    # is truncated rather than wrapped, and cannot shift a `path:N` jump.
    local theme
    theme="$(_bat_theme_flag)"
    if _fits_in_pane "$target"; then
      # Short file: pipe it so pad_to_pane_height can fill the pane and the
      # text renders from the TOP (see that function for the why). Costs
      # nothing here, since LESSOPEN was already feeding less from a pipe.
      # shellcheck disable=SC2086
      bat --color=always $theme --style=numbers "$target" \
        | pad_left | pad_to_pane_height \
        | less -R "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${line:++$line}
      return 0
    fi
    # Long file: already fills the pane, so keep less file-backed (seekable,
    # shows a real percentage) instead of buffering a pipe.
    # LESSOPEN is a command STRING that less hands to a shell, so the inner
    # quotes are meant literally and the shell does respect them; that is
    # what SC2089/SC2090 warn about and why an array cannot be used here.
    # shellcheck disable=SC2089
    LESSOPEN="|bat --color=always $theme--style=numbers %s | sed 's/^/  /'"
    # shellcheck disable=SC2090
    export LESSOPEN
    exec less -R "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${line:++$line} "$target"
  fi
  if _fits_in_pane "$target"; then
    pad_left < "$target" | pad_to_pane_height \
      | less -N "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${line:++$line}
    return 0
  fi
  exec less -N "${lesskey_args[@]}" "${PAGER_PROMPT_ARGS[@]}" ${line:++$line} "$target"
}
