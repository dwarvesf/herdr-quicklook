# shellcheck shell=bash
# json.sh: json render-registry renderer (v0.4 SG-06/P2). Pretty-prints via
# `jq .` (fixes minified/single-line json), paged through
# render_command_in_pager. Absent `jq` declines to the TEXT renderer (json
# is still perfectly readable, if less pretty, as plain text) rather than
# the fallback guard - same precedent as markdown.sh's glow-absent degrade
# and csv.sh's qsv-absent degrade. See the render-registry contract at the
# top of lib.sh.

# match_render_json <path>: owns `.json` files, but only when `jq` is on
# PATH (absent -> decline -> falls through the registry to `text`) AND
# file(1) reports a text encoding, not binary - the negative control this
# sub-goal's quality bar calls out (a binary-garbage file wearing a
# `.json` extension declines rather than being handed to jq).
match_render_json() {
  local path="$1" ext enc
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  [ "$ext" = "json" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  enc="$(file -b --mime-encoding -- "$path" 2>/dev/null)"
  [ "$enc" != "binary" ] && [ -n "$enc" ]
}

# render_json <path> [line]: `line` is accepted for render_<kind> signature
# parity but unused - a pretty-printed document has no line to jump to. A
# malformed-json file that still passed the mime-encoding check (it is
# still text) makes `jq .` print its own parse error to the pager instead
# of a render - an honest degrade, not a crash.
render_json() {
  local path="$1"
  render_command_in_pager jq . -- "$path"
}
