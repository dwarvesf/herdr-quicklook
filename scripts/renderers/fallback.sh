# shellcheck shell=bash
# fallback.sh: the always-on catch-all render-registry renderer (v0.4).
# This IS the floor of the whole registry - the guarantee that nothing ever
# dumps raw bytes into the pane, even for a file no later Wave has a real
# renderer for. match_render_fallback always matches; RENDER_KINDS keeps
# `fallback` last (see the render-registry contract comment at the top of
# lib.sh) so it only ever runs once every more-specific kind has declined.

match_render_fallback() {
  return 0
}

# _fallback_hexdump <path> -> a safe dump of roughly the first 1KB of
# <path> on stdout: hexyl (offset + hex + ASCII gutter) when it is on PATH,
# else xxd, else the base-system `od -A x -t x1` (the GNU-only `x1z`
# ASCII-gutter modifier is not available on macOS's BSD od, so this stays
# hex-only rather than pick a non-portable format). `head -c 1024` bounds
# the input BEFORE any dumper ever sees the bytes, so a multi-GB file never
# gets fully piped through. Every one of these three tools' own output is
# already a safe hex/ASCII-escaped text representation - not "the file's
# bytes", a description of them - which is the actual guarantee here: a
# control byte or an embedded terminal escape sequence in <path> can never
# reach the pane un-hexed, no matter which of the three ran. file(1) + one
# of xxd/od (never both missing on macOS/Linux) are the only hard deps;
# hexyl is a nice-to-have, never a requirement to function.
_fallback_hexdump() {
  local path="$1"
  if command -v hexyl >/dev/null 2>&1; then
    head -c 1024 -- "$path" | hexyl
  elif command -v xxd >/dev/null 2>&1; then
    head -c 1024 -- "$path" | xxd
  else
    head -c 1024 -- "$path" | od -A x -t x1
  fi
}

# _fallback_hint <path> -> "install <tool> for a richer preview of .<ext>
# files" on stdout when <path>'s extension maps (RENDER_HINTS, via
# render_hint_for_ext in lib.sh) to a real external tool that is NOT
# already on PATH. rc 1 (no output) when: no extension, no mapping, the
# mapping is `(builtin)` (zip/tar/plist already have no external-tool
# story), or the mapped tool IS installed (a genuinely unknown binary
# reaching fallback despite a known extension - nothing to recommend).
_fallback_hint() {
  local path="$1" ext tool
  ext="${path##*.}"
  [ "$ext" != "$path" ] || return 1
  tool="$(render_hint_for_ext "$ext")" || return 1
  [ "$tool" != '(builtin)' ] || return 1
  command -v "$tool" >/dev/null 2>&1 && return 1
  printf 'install %s for a richer preview of .%s files' "$tool" "$ext"
}

# render_fallback <path> [line]: the always-on guard - a `file(1)` one-line
# type description, a bounded first-KB hexdump (_fallback_hexdump), and a
# targeted install hint (_fallback_hint), paged through `less`. `less -R`
# is a no-op passthrough when stdout is not a real terminal (e.g. under
# bats), the same convention render_command_in_pager relies on in lib.sh.
# `line` is accepted (signature parity with every other render_<kind>) but
# unused: a byte-safe type description has no concept of a line to jump to.
render_fallback() {
  local path="$1" desc hint
  desc="$(file -b -- "$path" 2>/dev/null)"
  [ -n "$desc" ] || desc="unknown file type"
  hint="$(_fallback_hint "$path")" || hint=""
  {
    printf 'quicklook: no specific renderer for this file yet\n'
    printf '  path: %s\n' "$path"
    printf '  type: %s\n\n' "$desc"
    _fallback_hexdump "$path"
    [ -n "$hint" ] && printf '\n  hint: %s\n' "$hint"
  } | less -R
  return 0
}
