# shellcheck shell=bash
# url.sh: any other http(s) URL. github.sh is checked first in HANDLER_KINDS
# and claims the github-shaped URLs, so this only ever sees generic ones.
# shellcheck disable=SC2034  # RESOLVED_* are consumed by the caller (resolve_any_token's caller)

match_url() {
  [ "$(classify_token "$1")" = "url" ]
}

handle_url() {
  RESOLVED_TARGET="$1"
  # A bare domain has no scheme; the browser opener needs one.
  case "$1" in
    http://* | https://*) ;;
    *) RESOLVED_TARGET="https://$1" ;;
  esac
  RESOLVED_LINE=""
  RESOLVED_MODE="browser"
  return 0
}
