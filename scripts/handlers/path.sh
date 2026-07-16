# shellcheck shell=bash
# path.sh: the catch-all kind, a filesystem path (optionally "path:line").
# match_path always succeeds, so it MUST stay last in HANDLER_KINDS - see the
# ordering note in the contract comment at the top of lib.sh.
# shellcheck disable=SC2034  # RESOLVED_* are consumed by the caller (resolve_any_token's caller)

match_path() {
  [ "$(classify_token "$1")" = "path" ]
}

handle_path() {
  parse_token "$1"
  local t
  t="$(resolve "$CLIP_PATH")" || return 1
  RESOLVED_TARGET="$t"
  RESOLVED_LINE="$CLIP_LINE"
  RESOLVED_MODE="file"
}
