# shellcheck shell=bash
# media.sh: media render-registry renderer (v0.4 SG-07, P3 pack). `ffprobe`
# metadata (duration/codec/dims/bitrate) always; for video (mp4/mov)
# additionally an `ffmpeg` first-frame poster drawn via `render_image`
# (SG-04) - reuse BY CALLING, never a duplicated chafa invocation. mp3 is
# metadata-only (no poster - there is no frame to extract from audio).
#
# HARD SAFETY RULE (this sub-goal's own quality bar): media renderers must
# NEVER attempt playback and must NEVER hang the pane on a bad/huge file.
# Enforced three ways: (1) ffmpeg is only ever told to WRITE a single frame
# to a poster FILE (`-frames:v 1`) - it is never pointed at an audio/video
# OUTPUT DEVICE, so there is no code path that could start playback; (2)
# every ffprobe/ffmpeg call runs through `_media_run_bounded`, a portable
# (bash 3.2-safe, no GNU-only `timeout`/`gtimeout` dependency) soft-timeout
# wrapper - a hung or huge-file probe is killed, never left to block the
# pane; (3) `</dev/null` on the ffmpeg call - ffmpeg prompts on stdin for an
# overwrite confirmation in some builds even with `-y`, and a prompt with no
# real stdin would otherwise hang forever waiting for input that can never
# arrive from a herdr pane.

# _MEDIA_TIMEOUT_SECS: the soft-timeout bound for every ffprobe/ffmpeg call
# below. Overridable for tests/tuning without editing the script.
_MEDIA_TIMEOUT_SECS="${QUICKLOOK_MEDIA_TIMEOUT:-5}"

# _media_run_bounded <secs> <argv...>: runs argv in the background and polls
# it (0.2s ticks) against a wall-clock deadline, SIGTERM-then-SIGKILL-ing it
# if it is still alive once <secs> has elapsed; returns argv's own exit
# status in the normal case. Pure bash - no `timeout`/`gtimeout` binary
# required (macOS ships neither by default). argv's stdout/stderr are
# inherited as-is, so a caller capturing `$(...)` still gets its output.
#
# POLLING, NOT a backgrounded `sleep <secs>` watcher that signals this
# function's own PID: an earlier version raced a `( sleep "$secs"; kill -TERM
# "$pid" ) &` watcher against `wait "$pid"`, then tried to `kill "$watcher"`
# once the main command finished early. That watcher subshell is itself
# BLOCKED inside its own `sleep` call when the signal arrives - bash defers
# an async signal's delivery until the shell's current foreground command
# returns - so `kill "$watcher"` silently did nothing until `sleep "$secs"`
# ran to completion on its own: EVERY bounded call paid the FULL timeout
# even when the wrapped command finished instantly (measured: a 5s bound
# turned a <1s stubbed ffprobe call into a flat 5s, visible as bats -T
# reporting ~5s/~10s per render_media test). Live-verified against the
# rewrite below (see DECISIONS.md). Polling this function's OWN loop instead
# never blocks on a foreign process's signal-deferral window.
_media_run_bounded() {
  local secs="$1" pid rc start now
  shift
  "$@" &
  pid=$!
  start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s)
    [ $((now - start)) -ge "$secs" ] && break
    sleep 0.2 2>/dev/null
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null
    sleep 0.2 2>/dev/null
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  rc=$?
  return "$rc"
}

# match_render_media <path>: extension gate (mp4/mov/mp3) PLUS the tool(s)
# that kind's render actually needs - mp4/mov need BOTH ffprobe (metadata)
# and ffmpeg (poster frame); mp3 needs only ffprobe (metadata-only, no
# poster) so a box with ffprobe but no ffmpeg still gets audio metadata
# instead of an unnecessary decline - PLUS a real `file --mime-type` check
# (a renamed non-media file declines here, the negative control this
# sub-goal's quality bar calls out).
match_render_media() {
  local path="$1" ext mime
  [ -f "$path" ] || return 1
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    mp4 | mov)
      command -v ffprobe >/dev/null 2>&1 || return 1
      command -v ffmpeg >/dev/null 2>&1 || return 1
      ;;
    mp3)
      command -v ffprobe >/dev/null 2>&1 || return 1
      ;;
    *) return 1 ;;
  esac
  mime="$(file -b --mime-type -- "$path" 2>/dev/null)"
  case "$ext" in
    mp4) [ "$mime" = "video/mp4" ] ;;
    mov) [ "$mime" = "video/quicktime" ] || [ "$mime" = "video/mp4" ] ;;
    mp3) [ "$mime" = "audio/mpeg" ] || [ "$mime" = "audio/mp3" ] ;;
  esac
}

# _media_ffprobe_summary <path>: a bounded `ffprobe` call for duration,
# bitrate, container name, and per-stream codec/dimensions/sample-rate -
# metadata only, never frame or sample data. Empty/failed probe still
# returns a printable (non-empty) summary, so the caller never has to
# special-case "no output".
_media_ffprobe_summary() {
  local path="$1" out
  out="$(_media_run_bounded "$_MEDIA_TIMEOUT_SECS" ffprobe -v error -hide_banner \
    -show_entries 'format=duration,bit_rate,format_name:stream=codec_name,codec_type,width,height,sample_rate,channels' \
    -of default=noprint_wrappers=0 -- "$path" 2>&1)"
  [ -n "$out" ] || out="(no metadata available)"
  printf 'file: %s\n\n%s\n' "$path" "$out"
}

# _media_extract_poster <path> <out.png>: a bounded, single-frame `ffmpeg`
# extraction at the very first frame (`-frames:v 1`) - never a playback
# invocation, never an output device, `</dev/null` so a build that still
# prompts for overwrite confirmation can never hang waiting on stdin.
# Returns 1 (caller degrades to metadata-only) on any failure or empty
# output, e.g. a corrupt file, an unsupported codec, or the timeout firing.
_media_extract_poster() {
  local path="$1" out="$2"
  _media_run_bounded "$_MEDIA_TIMEOUT_SECS" \
    ffmpeg -v error -y -ss 0 -i "$path" -frames:v 1 -q:v 2 -- "$out" </dev/null
  [ -s "$out" ]
}

# render_media <path> [line]: mp3 pages the metadata summary through `less`
# (same paged-text shape as sqlite/plist); mp4/mov prints the metadata
# summary then draws the poster frame inline via `render_image` (SG-04) when
# extraction succeeds, degrading to a metadata-only paged view when it does
# not (a corrupt video, an unsupported codec, or the bound firing - never a
# crash, never a raw-byte dump). `line` accepted for signature parity,
# unused - there is no line to jump to in a media summary.
render_media() {
  local path="$1" ext meta poster rc
  ext="$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')"
  meta="$(_media_ffprobe_summary "$path")"
  if [ "$ext" = "mp3" ]; then
    printf '%s' "$meta" | less -R
    return 0
  fi
  poster="$(mktemp "${TMPDIR:-/tmp}/herdr-quicklook-media.XXXXXX.png" 2>/dev/null)" || poster=""
  if [ -n "$poster" ] && _media_extract_poster "$path" "$poster"; then
    printf '%s\n' "$meta"
    render_image "$poster"
    rc=$?
    rm -f -- "$poster"
    return $rc
  fi
  [ -n "$poster" ] && rm -f -- "$poster"
  printf '%s\n(no poster frame available)\n' "$meta" | less -R
  return 0
}
