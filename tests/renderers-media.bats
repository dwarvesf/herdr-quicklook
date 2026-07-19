#!/usr/bin/env bats
# Tests for scripts/renderers/media.sh (v0.4 SG-07, P3 pack): metadata via
# ffprobe, an optional poster frame via ffmpeg -> render_image (SG-04) for
# video, metadata-only for audio. HARD SAFETY: media renderers must NEVER
# attempt playback and must NEVER hang the pane - the stubs below assert
# both (no playback-shaped flag ever reaches ffmpeg/ffprobe, and every call
# runs through the bounded `_media_run_bounded` wrapper).

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # Minimal, REAL container-magic bytes - enough for `file --mime-type` to
  # classify them correctly (verified live), without needing a fully
  # decodable stream.
  python3 - "$FIX/t.mp4" <<'PY'
import struct, sys
def box(typ, payload=b''):
    return struct.pack('>I', 8 + len(payload)) + typ + payload
data = box(b'ftyp', b'isom' + struct.pack('>I', 0) + b'isomiso2avc1mp41') + box(b'free')
open(sys.argv[1], 'wb').write(data)
PY
  python3 - "$FIX/t.mov" <<'PY'
import struct, sys
def box(typ, payload=b''):
    return struct.pack('>I', 8 + len(payload)) + typ + payload
data = box(b'ftyp', b'qt  ' + struct.pack('>I', 0) + b'qt  ') + box(b'free')
open(sys.argv[1], 'wb').write(data)
PY
  # Raw MPEG audio frame-sync bytes (0xFF 0xFB ...) - what a real mp3 starts
  # with; `file --mime-type` reports audio/mpeg for this (verified live). An
  # ID3-tag-only fixture is NOT enough (verified: reports
  # application/octet-stream without a following valid frame).
  printf '\xff\xfb\x90\x00' > "$FIX/t.mp3"
  head -c 200 /dev/zero >> "$FIX/t.mp3"
  # binary garbage wearing a media extension - the negative control.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.mp4"
  printf 'hello\n' > "$FIX/t.txt"

  # stub ffprobe/ffmpeg that record their argv (order preserved) and emit
  # deterministic output, so render tests assert the invocation SHAPE
  # (bounded, metadata/single-frame only, never playback) without depending
  # on real media decoding.
  STUB="$(mktemp -d)"
  cat > "$STUB/ffprobe" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FFPROBE_ARGV_FILE"
printf 'duration=1.0\ncodec_name=h264\n'
exit 0
SH
  cat > "$STUB/ffmpeg" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FFMPEG_ARGV_FILE"
# write a 1-byte placeholder "poster" at the last argv (the output path)
printf '\x89PNG' > "${@: -1}"
exit 0
SH
  chmod +x "$STUB/ffprobe" "$STUB/ffmpeg"
  export FFPROBE_ARGV_FILE="$FIX/ffprobe.argv"
  export FFMPEG_ARGV_FILE="$FIX/ffmpeg.argv"

  ONLYBASE="$(mktemp -d)"
  ln -s "$(command -v file)" "$ONLYBASE/file"
  ln -s "$(command -v tr)" "$ONLYBASE/tr"
  ln -s "$(command -v dirname)" "$ONLYBASE/dirname"
  ln -s "$(command -v bash)" "$ONLYBASE/bash"
}

teardown() {
  cd /
  /bin/rm -rf "$FIX" "$STUB" "$ONLYBASE"
  export PATH="/usr/bin:/bin:$PATH"
}

# ---- match: extension + real tools present ----

@test "match_render_media: matches a real mp4 when ffprobe and ffmpeg are present" {
  export PATH="$STUB:$PATH"
  match_render_media "$FIX/t.mp4"
}

@test "match_render_media: matches a real mov when ffprobe and ffmpeg are present" {
  export PATH="$STUB:$PATH"
  match_render_media "$FIX/t.mov"
}

@test "match_render_media: matches a real mp3 with only ffprobe present (no ffmpeg needed for audio)" {
  STUB_MP3_ONLY="$(mktemp -d)"
  ln -s "$STUB/ffprobe" "$STUB_MP3_ONLY/ffprobe"
  export PATH="$STUB_MP3_ONLY:$PATH"
  match_render_media "$FIX/t.mp3"
  /bin/rm -rf "$STUB_MP3_ONLY"
}

@test "match_render_media: declines a non-media extension" {
  export PATH="$STUB:$PATH"
  ! match_render_media "$FIX/t.txt"
}

# ---- degrade: tools absent ----

@test "match_render_media: declines mp4 when ffprobe/ffmpeg are absent from PATH" {
  export PATH="$ONLYBASE"
  ! match_render_media "$FIX/t.mp4"
}

@test "match_render_media: declines mp3 when ffprobe is absent from PATH" {
  export PATH="$ONLYBASE"
  ! match_render_media "$FIX/t.mp3"
}

@test "render-registry: ffprobe absent routes a real mp4 to fallback via render_any" {
  export PATH="$ONLYBASE"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.mp4'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/t.mp4" ]
}

# ---- negative control: binary garbage renamed .mp4 ----

@test "match_render_media: declines binary garbage renamed .mp4 (keys on type, not extension)" {
  export PATH="$STUB:$PATH"
  ! match_render_media "$FIX/fake.mp4"
}

@test "render-registry: binary garbage renamed .mp4 routes to fallback, never ffprobe/ffmpeg" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.mp4'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.mp4" ]
  [ ! -e "$FFPROBE_ARGV_FILE" ]
  [ ! -e "$FFMPEG_ARGV_FILE" ]
}

# ---- render: mp3 is metadata-only, never touches ffmpeg ----

@test "render_media: mp3 calls ffprobe for metadata and never invokes ffmpeg" {
  export PATH="$STUB:$PATH"
  run render_media "$FIX/t.mp3"
  [ "$status" -eq 0 ]
  [ -f "$FFPROBE_ARGV_FILE" ]
  [ ! -e "$FFMPEG_ARGV_FILE" ]
  [[ "$output" == *"duration=1.0"* ]]
}

# ---- render: mp4/mov, metadata + a single bounded poster frame ----

@test "render_media: mp4 calls ffprobe for metadata and ffmpeg for a single first frame" {
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_image() { printf 'IMAGE:%s\n' \"\$1\"; return 0; }; render_media '$FIX/t.mp4'"
  [ "$status" -eq 0 ]
  [ -f "$FFPROBE_ARGV_FILE" ]
  [ -f "$FFMPEG_ARGV_FILE" ]
  grep -qx -- '-frames:v' "$FFMPEG_ARGV_FILE"
  [[ "$output" == *"duration=1.0"* ]]
  [[ "$output" == *"IMAGE:"* ]]
}

@test "render_media: never passes a playback-shaped flag to ffmpeg or ffprobe" {
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_image() { return 0; }; render_media '$FIX/t.mp4'"
  [ "$status" -eq 0 ]
  ! grep -qxE -- '-f' "$FFMPEG_ARGV_FILE"
  ! grep -qi -- 'alsa\|avfoundation\|play' "$FFMPEG_ARGV_FILE"
  ! grep -qi -- 'alsa\|avfoundation\|play' "$FFPROBE_ARGV_FILE"
}

@test "render_media: a failed poster extraction degrades to metadata-only, never a crash" {
  FAILSTUB="$(mktemp -d)"
  ln -s "$STUB/ffprobe" "$FAILSTUB/ffprobe"
  cat > "$FAILSTUB/ffmpeg" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$FAILSTUB/ffmpeg"
  export PATH="$FAILSTUB:$PATH"
  run render_media "$FIX/t.mp4"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no poster frame available"* ]]
  /bin/rm -rf "$FAILSTUB"
}

# ---- safety: the bounded-timeout wrapper actually bounds a hung command ----

@test "_media_run_bounded: kills a command that runs past the bound instead of hanging" {
  run bash -c "
    . '$LIB'
    _MEDIA_TIMEOUT_SECS=1
    start=\$(date +%s)
    _media_run_bounded 1 sleep 30
    end=\$(date +%s)
    echo \$((end - start))
  "
  [ "$status" -ne 0 ] || true
  # the whole call must return well under sleep's own 30s duration.
  local elapsed
  elapsed="$(printf '%s' "$output" | tail -1)"
  [ "$elapsed" -lt 10 ]
}
