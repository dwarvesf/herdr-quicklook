#!/usr/bin/env bash
# Opt-in pane.agent_status_changed hook. Capture a turn baseline when work
# starts, then scan only newly produced text when the agent becomes idle.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

load_config
mode="${QUICKLOOK_AGENT_SUGGESTIONS:-off}"
case "$mode" in
  notify | preview) ;;
  *) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0
event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
[ -n "$event_json" ] || exit 0
status="$(printf '%s' "$event_json" | jq -r '.data.agent_status // empty' 2>/dev/null || true)"
pane_id="$(printf '%s' "$event_json" | jq -r '.data.pane_id // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" | jq -r '.focused_pane_cwd // .workspace_cwd // empty' 2>/dev/null || true)"
case "$pane_id" in
  '' | *[!A-Za-z0-9._-]*) exit 0 ;;
esac

lines="${QUICKLOOK_AGENT_SCAN_LINES:-300}"
case "$lines" in
  '' | *[!0-9]*) lines=300 ;;
esac
[ "$lines" -gt 0 ] 2>/dev/null || lines=300

state_root="${HERDR_PLUGIN_STATE_DIR:-$(recents_state_dir)}/agent-suggestions"
mkdir -p -- "$state_root" 2>/dev/null || exit 0
lock="$state_root/$pane_id.lock"
if [ -d "$lock" ] && [ ! -L "$lock" ]; then
  rm -rf -- "$lock" 2>/dev/null || exit 0
fi
acquired=0
attempt=0
while [ "$attempt" -lt 20 ]; do
  if ln -s "$$" "$lock" 2>/dev/null; then
    acquired=1
    break
  fi
  owner="$(readlink "$lock" 2>/dev/null || true)"
  case "$owner" in
    '' | *[!0-9]*) rm -rf -- "$lock" 2>/dev/null || true ;;
    *) kill -0 "$owner" 2>/dev/null || rm -f -- "$lock" 2>/dev/null || true ;;
  esac
  attempt=$((attempt + 1))
  sleep 0.05
done
[ "$acquired" -eq 1 ] || exit 0

tmp_current=""
tmp_delta=""
tmp_latest=""
cleanup() {
  [ -z "$tmp_current" ] || rm -f -- "$tmp_current"
  [ -z "$tmp_delta" ] || rm -f -- "$tmp_delta"
  [ -z "$tmp_latest" ] || rm -f -- "$tmp_latest"
  rm -f -- "$lock" 2>/dev/null || true
}
trap cleanup EXIT

baseline="$state_root/$pane_id.baseline"
if [ "$status" = "working" ]; then
  [ -f "$baseline" ] && exit 0
  tmp_current="$(mktemp "$state_root/.baseline.XXXXXX" 2>/dev/null)" || exit 0
  if "$herdr_bin" pane read "$pane_id" --source recent-unwrapped --lines "$lines" --format text >"$tmp_current" 2>/dev/null; then
    mv -f -- "$tmp_current" "$baseline"
    tmp_current=""
  fi
  exit 0
fi

case "$status" in
  done | idle) ;;
  *) exit 0 ;;
esac
[ -f "$baseline" ] || exit 0

tmp_current="$(mktemp "$state_root/.current.XXXXXX" 2>/dev/null)" || exit 0
"$herdr_bin" pane read "$pane_id" --source recent-unwrapped --lines "$lines" --format text >"$tmp_current" 2>/dev/null || exit 0
tmp_delta="$(mktemp "$state_root/.delta.XXXXXX" 2>/dev/null)" || exit 0
awk '
  FILENAME == ARGV[1] { baseline[FNR] = $0; baseline_lines = FNR; next }
  !changed && FNR <= baseline_lines && $0 == baseline[FNR] { next }
  { changed = 1; print }
' "$baseline" "$tmp_current" >"$tmp_delta"
rm -f -- "$baseline"

if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  cd "$cwd" || exit 0
fi
candidate="$(pick_scan_text <"$tmp_delta" | head -1)"
[ -n "$candidate" ] || exit 0
IFS=$'\t' read -r token kind _ <<<"$candidate"
[ -n "$token" ] || exit 0

latest="$state_root/latest.json"
tmp_latest="$(mktemp "$state_root/.latest.XXXXXX" 2>/dev/null)" || exit 0
jq -n \
  --arg token "$token" \
  --arg kind "$kind" \
  --arg pane_id "$pane_id" \
  --arg cwd "$cwd" \
  '{token: $token, kind: $kind, pane_id: $pane_id, cwd: $cwd}' >"$tmp_latest" || exit 0
mv -f -- "$tmp_latest" "$latest"
tmp_latest=""

if [ "$mode" = "preview" ]; then
  bash "$script_dir/open-suggestion.sh"
else
  "$herdr_bin" notification show "quicklook suggestion" --body "$token" >/dev/null 2>&1 || true
fi
