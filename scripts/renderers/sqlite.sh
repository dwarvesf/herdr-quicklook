# shellcheck shell=bash
# sqlite.sh: sqlite-database render-registry renderer (v0.4 SG-07, P3 pack).
# Shows the table list + schema only, via `sqlite3 -readonly` - NEVER a row
# dump. See the render-registry contract at the top of lib.sh.

# match_render_sqlite <path>: extension gate (.sqlite/.db) PLUS sqlite3 on
# PATH PLUS a real `file --mime-type` check (libmagic recognizes the SQLite
# file-format magic reliably; a renamed non-database file reports a generic
# mime and declines here - the negative control this sub-goal's quality bar
# calls out).
match_render_sqlite() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    sqlite | db) ;;
    *) return 1 ;;
  esac
  command -v sqlite3 >/dev/null 2>&1 || return 1
  mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
  [ "$mime" = "application/vnd.sqlite3" ]
}

# render_sqlite <path> [line]: SAFETY - `-readonly` opens the database file
# in SQLite's own read-only mode (a write attempt errors, it does not
# silently fall through to read-write), and the two dot-commands run here
# are `.tables` (table list) and `.schema` (DDL) - never a `SELECT`, so a
# multi-gigabyte table is never scanned or dumped. Paged through `less -R`
# via the shared `render_command_in_pager` helper (same shape as
# markdown.sh/plist.sh), not a duplicated pager invocation. `line` accepted
# for signature parity, unused - there is no line to jump to in a schema
# dump.
render_sqlite() {
  local path="$1"
  render_command_in_pager sqlite3 -readonly -cmd '.tables' -- "$path" '.schema'
}
