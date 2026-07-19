# shellcheck shell=bash
# pdf.sh: pdf render-registry renderer (v0.4 SG-06/P2). Two independent
# poppler-backed modes, run together when both are available: a page-1
# POSTER (`pdftoppm` -> a temp PNG -> image.sh's render_image, the SAME
# chafa invocation image.sh already uses, never re-implemented) and a TEXT
# extraction (`pdftotext ... -` paged through render_command_in_pager).
# Either mode alone is still a useful render, so this renderer degrades in
# three tiers per the ROADMAP type->tool map: poster+text -> text-only (no
# pdftoppm/chafa) -> decline (no poppler at all - a real-world pdf's binary
# stream content then falls through the registry to `fallback`). See the
# render-registry contract at the top of lib.sh.

_pdf_have_poster() {
  command -v pdftoppm >/dev/null 2>&1 && command -v chafa >/dev/null 2>&1
}

_pdf_have_text() {
  command -v pdftotext >/dev/null 2>&1
}

# match_render_pdf <path>: owns `.pdf` files reported as application/pdf by
# file(1) (extension alone would let a renamed non-pdf file through), but
# only when at least ONE poppler mode is usable - poster (pdftoppm+chafa)
# or text (pdftotext). Neither present -> decline.
match_render_pdf() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  [ "$ext" = "pdf" ] || return 1
  mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
  [ "$mime" = "application/pdf" ] || return 1
  _pdf_have_poster || _pdf_have_text
}

# render_pdf <path> [line]: draws the page-1 poster first (when available),
# then pages the extracted text (when available). `line` is accepted for
# render_<kind> signature parity but unused - neither poppler mode has a
# line-jump concept. A poster conversion failure (a corrupt pdf that still
# passed the mime check) is swallowed - text mode (or nothing, if that is
# also unavailable) still runs; match_render_pdf already guaranteed at
# least one mode is usable. The temp PNG is always removed.
render_pdf() {
  local path="$1" tmp_prefix tmp_png
  if _pdf_have_poster; then
    tmp_prefix="$(mktemp "${TMPDIR:-/tmp}/herdr-quicklook-pdf-XXXXXX" 2>/dev/null)" || tmp_prefix=""
    if [ -n "$tmp_prefix" ]; then
      rm -f -- "$tmp_prefix"
      if pdftoppm -png -f 1 -l 1 -singlefile -- "$path" "$tmp_prefix" 2>/dev/null; then
        tmp_png="$tmp_prefix.png"
        [ -f "$tmp_png" ] && render_image "$tmp_png"
        rm -f -- "$tmp_png"
      fi
    fi
  fi
  if _pdf_have_text; then
    render_command_in_pager pdftotext -- "$path" -
    return $?
  fi
  return 0
}
