# shellcheck shell=bash
# plist.sh: property-list render-registry renderer (v0.4 SG-07, P3 pack).
# `plutil` is base-system on macOS (never installed by scripts/
# install-renderers.sh, see its own base-system note) and has no Linux
# equivalent - absent, this kind declines outright (no XML/binary-plist
# degrade path exists without it). See the render-registry contract at the
# top of lib.sh.

# match_render_plist <path>: extension gate (.plist) PLUS plutil on PATH
# PLUS `plutil -lint -s` actually validating the file. This doubles as the
# type check AND the negative control this sub-goal's quality bar calls out
# in one step: a binary plist's `file --mime-type` is a generic
# `application/octet-stream` (verified - libmagic has no distinct bplist
# signature check on this host), so a mime-type gate (the pattern every
# other P3 kind uses) would either over-accept garbage or under-accept a
# real binary plist; `plutil -lint` itself is the ground truth for "is this
# really a plist" regardless of the XML/binary/JSON serialization plutil
# supports, and it rejects garbage.
match_render_plist() {
  local path="$1" ext
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  [ "$ext" = "plist" ] || return 1
  command -v plutil >/dev/null 2>&1 || return 1
  plutil -lint -s -- "$path" >/dev/null 2>&1
}

# render_plist <path> [line]: `plutil -p` (a structured, human-readable
# dump - not the raw XML/binary bytes), paged through `less -R` via the
# shared `render_command_in_pager` helper (same shape as markdown.sh/
# sqlite.sh), not a duplicated pager invocation. `line` accepted for
# signature parity, unused - there is no line to jump to in a plist dump.
render_plist() {
  local path="$1"
  render_command_in_pager plutil -p -- "$path"
}
