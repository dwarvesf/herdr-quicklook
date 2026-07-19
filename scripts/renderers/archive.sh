# shellcheck shell=bash
# archive.sh: archive render-registry renderer (v0.4 SG-06/P2). A CONTENT
# LISTING, not extraction - `unzip -l` for zip/jar, `tar -tf` for tar/tgz -
# paged through render_command_in_pager. unzip/tar are base-system on
# macOS + Linux, so this kind rarely degrades (per the ROADMAP type->tool
# map); the always-on `fallback` renderer is still the floor if a listing
# tool is somehow absent. See the render-registry contract at the top of
# lib.sh.

# _archive_kind <path> -> the four supported extensions, lowercased,
# normalized so match/render do the extension work once each.
_archive_kind() {
  printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]'
}

# match_render_archive <path>: owns zip/tar/tgz/jar files, gated on BOTH the
# listing tool being on PATH (unzip for zip/jar, tar for tar/tgz - absent
# -> decline -> fallback, the rare base-system-missing degrade) AND file(1)
# confirming the archive's real mime type - the negative control this
# sub-goal's quality bar calls out (a renamed non-archive file declines
# rather than being handed to unzip/tar).
match_render_archive() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  ext="$(_archive_kind "$path")"
  case "$ext" in
    zip | jar)
      command -v unzip >/dev/null 2>&1 || return 1
      mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
      [ "$mime" = "application/zip" ]
      ;;
    tar)
      command -v tar >/dev/null 2>&1 || return 1
      mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
      [ "$mime" = "application/x-tar" ]
      ;;
    tgz)
      command -v tar >/dev/null 2>&1 || return 1
      mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
      [ "$mime" = "application/gzip" ]
      ;;
    *) return 1 ;;
  esac
}

# render_archive <path> [line]: pages the listing. `line` is accepted for
# render_<kind> signature parity but unused - a listing has no line to jump
# to. tar's invocation deliberately omits the `--` end-of-options marker
# every other renderer in this pack uses: macOS's bundled bsdtar mis-parses
# `tar -tf -- <path>` (`tar: --: m: No such file or directory`, verified
# interactively) even though `unzip -l -- <path>` handles it fine.
# `resolve()` in lib.sh only ever hands renderers an ABSOLUTE path, so a
# bare `tar -tf <path>` is never at risk of the path being misread as a
# flag.
render_archive() {
  local path="$1" ext
  ext="$(_archive_kind "$path")"
  case "$ext" in
    zip | jar) render_command_in_pager unzip -l -- "$path" ;;
    tar | tgz) render_command_in_pager tar -tf "$path" ;;
  esac
}
