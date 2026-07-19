# shellcheck shell=bash
# csv.sh: csv/tsv render-registry renderer (v0.4 SG-06/P2). Draws an
# aligned table via `qsv table`, paged through render_command_in_pager.
# Absent `qsv` declines to the TEXT renderer (a csv/tsv is still perfectly
# readable as plain text) rather than the fallback guard - same precedent
# as markdown.sh's glow-absent degrade. See the render-registry contract at
# the top of lib.sh.

# match_render_csv <path>: owns `.csv`/`.tsv` files, but only when `qsv` is
# on PATH (absent -> decline -> falls through the registry to `text`, since
# csv/tsv content is textual) AND file(1) reports a text encoding, not
# binary - the negative control this sub-goal's quality bar calls out (a
# binary-garbage file wearing a `.csv`/`.tsv` extension declines rather
# than being handed to qsv).
match_render_csv() {
  local path="$1" ext enc
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    csv | tsv) ;;
    *) return 1 ;;
  esac
  command -v qsv >/dev/null 2>&1 || return 1
  enc="$(file -b --mime-encoding -- "$path" 2>/dev/null)"
  [ "$enc" != "binary" ] && [ -n "$enc" ]
}

# render_csv <path> [line]: `.tsv` gets an explicit tab delimiter (qsv's
# own default is comma); `.csv` uses qsv's default. `line` is accepted for
# render_<kind> signature parity but unused - an aligned table has no line
# to jump to.
render_csv() {
  local path="$1" ext
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  if [ "$ext" = "tsv" ]; then
    render_command_in_pager qsv table -d "$(printf '\t')" -- "$path"
  else
    render_command_in_pager qsv table -- "$path"
  fi
}
