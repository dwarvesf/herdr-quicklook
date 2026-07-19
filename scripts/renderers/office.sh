# shellcheck shell=bash
# office.sh: office-document render-registry renderer (v0.4 SG-07, P3 pack).
# `docx` and `xlsx` both convert through `pandoc -t markdown` (pandoc's docx
# reader is long-standing; its xlsx reader emits one `## <SheetName>` heading
# per sheet, each followed by the sheet's cells as a markdown table) and are
# handed to `render_markdown` (SG-03) - reuse BY CALLING, never a duplicated
# glow/pager invocation, same pattern ipynb.sh uses. xlsx is additionally
# clipped to the FIRST `##` heading block only (this sub-goal's "first sheet"
# requirement) - pandoc has no CSV writer (verified: `pandoc
# --list-output-formats` has no `csv` entry), so a real `-> csv -> reuse
# SG-06's csv renderer` path does not exist for pandoc; routing xlsx through
# the SAME markdown/glow path as docx (which pandoc DOES support end to end)
# is the deviation from the goal file's literal "xlsx -> csv" wording - noted
# in HANDOFF/DECISIONS. All writes happen to `mktemp` paths only.

# match_render_office <path>: extension gate (docx/xlsx) PLUS pandoc AND glow
# on PATH (both required - render_office always ends in render_markdown, so
# glow's presence is decided HERE, not mid-render) PLUS a real
# `file --mime-type` check for the specific OOXML content type (a renamed
# non-office zip, or raw binary garbage, reports a generic
# `application/zip`/`application/octet-stream` - not the OOXML
# wordprocessingml/spreadsheetml mime - and declines here, the negative
# control this sub-goal's quality bar calls out).
match_render_office() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    docx | xlsx) ;;
    *) return 1 ;;
  esac
  command -v pandoc >/dev/null 2>&1 || return 1
  command -v glow >/dev/null 2>&1 || return 1
  mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
  case "$ext" in
    docx) [ "$mime" = "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ] ;;
    xlsx) [ "$mime" = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ] ;;
  esac
}

# _office_first_sheet_only: reads pandoc's xlsx->markdown output on stdin,
# writes only the FIRST `## ` heading block (that heading line through the
# line before the next `## ` heading, or EOF) on stdout - the "first sheet"
# view a multi-sheet workbook needs. A docx conversion has no `## `-per-sheet
# shape, so this is only ever called on the xlsx branch.
_office_first_sheet_only() {
  awk '/^## / { n++; if (n == 2) exit } { print }'
}

# render_office <path> [line]: converts to a `mktemp` markdown file (docx:
# the full pandoc conversion; xlsx: piped through _office_first_sheet_only
# first), a failed or empty conversion becomes a short in-pager notice
# instead of a blank render, then hands the file to `render_markdown` and
# returns ITS exit status. `line` accepted for signature parity, unused.
#
# The pandoc pipeline runs INLINE in this function body so
# `${PIPESTATUS[0]}` reads pandoc's real exit status - see ipynb.sh's
# render_ipynb for why a helper-function indirection would silently read 0
# instead (PIPESTATUS does not cross a function-call boundary in bash).
render_office() {
  local path="$1" ext tmp rc
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  tmp="$(mktemp "${TMPDIR:-/tmp}/herdr-quicklook-office.XXXXXX.md" 2>/dev/null)" || {
    render_fallback "$path"
    return $?
  }
  if [ "$ext" = "xlsx" ]; then
    pandoc -f xlsx -t markdown -- "$path" 2>/dev/null | _office_first_sheet_only >"$tmp"
    rc=${PIPESTATUS[0]}
  else
    pandoc -f docx -t markdown -- "$path" >"$tmp" 2>/dev/null
    rc=$?
  fi
  if [ "$rc" -ne 0 ] || [ ! -s "$tmp" ]; then
    printf 'quicklook: pandoc could not convert this %s file\n  path: %s\n' "$ext" "$path" >"$tmp"
  fi
  render_markdown "$tmp"
  rc=$?
  rm -f -- "$tmp"
  return $rc
}
