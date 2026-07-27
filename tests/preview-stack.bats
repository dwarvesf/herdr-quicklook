#!/usr/bin/env bats
# Unit coverage for the preview-stack helpers, which until now were exercised
# only by hand against a live pane: pane_is_preview, push_resolved_into_pane,
# push_into_preview, emit_any and line_numbers_on. `mutation-sweep.sh
# --unmentioned` listed all five, i.e. no test file even named them.
#
# Every push case carries a NEGATIVE control (nothing must be sent), because
# a "did it send the right keys" assertion passes just as happily when the
# code sends nothing at all and the marker file is simply absent.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/repo"
  git -C "$FIX/repo" init -q -b main
  printf '# target\n' > "$FIX/repo/target.md"
  printf 'code\n' > "$FIX/repo/code.sh"

  MARKER="$FIX/sent.log"
  STUB="$(mktemp -d)"

  # herdr stub: answers `pane list` with a fixture roster, `pane
  # process-info` with a foreground that is `less` ONLY for the real preview
  # (p-prev) and an agent for the mislabeled one (p-mislabel), and records
  # every send-text / send-keys argv so a test can assert what was driven.
  cat > "$STUB/herdr" <<SH
#!/usr/bin/env bash
case "\$1 \$2" in
  "pane list")
    printf '%s' '{"result":{"panes":[
      {"pane_id":"p-prev","label":"Preview: target.md","cwd":"$FIX/repo"},
      {"pane_id":"p-mislabel","label":"Preview: stale.md","cwd":"$FIX/repo"},
      {"pane_id":"p-shell","label":null,"cwd":"$FIX/repo"},
      {"pane_id":"p-files","label":"Files","cwd":"$FIX/repo"}
    ]}}'
    ;;
  "pane process-info")
    fg=node
    [ "\$4" = "p-prev" ] && fg=less
    printf '{"result":{"process_info":{"foreground_processes":[{"name":"%s"}]}}}' "\$fg"
    ;;
  "pane send-text"|"pane send-keys") printf '%s\n' "\$*" >> "$MARKER" ;;
esac
exit 0
SH
  chmod +x "$STUB/herdr"
  export HERDR_BIN_PATH="$STUB/herdr"
  herdr_bin="$STUB/herdr"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

sent() { cat "$MARKER" 2>/dev/null; }

# ---- line_numbers_on ----

@test "line_numbers_on: off by default" {
  unset QUICKLOOK_LINE_NUMBERS
  ! line_numbers_on
}

@test "line_numbers_on: on only for exactly 1" {
  QUICKLOOK_LINE_NUMBERS=1 line_numbers_on
  ! QUICKLOOK_LINE_NUMBERS=0 line_numbers_on
  ! QUICKLOOK_LINE_NUMBERS=yes line_numbers_on
}

# ---- pane_is_preview ----

@test "pane_is_preview: a Preview pane matches and echoes its cwd" {
  run pane_is_preview "p-prev"
  [ "$status" -eq 0 ]
  [ "$output" = "$FIX/repo" ]
}

@test "pane_is_preview: a plain shell pane does not match" {
  run pane_is_preview "p-shell"
  [ "$status" -ne 0 ]
}

@test "pane_is_preview: another plugin's pane does not match" {
  run pane_is_preview "p-files"
  [ "$status" -ne 0 ]
}

@test "pane_is_preview: an unknown pane id does not match" {
  run pane_is_preview "p-nope"
  [ "$status" -ne 0 ]
}

@test "pane_is_preview: an empty pane id does not match" {
  run pane_is_preview ""
  [ "$status" -ne 0 ]
}

# ---- push_resolved_into_pane ----

@test "push_resolved_into_pane: sends :e with the RESOLVED absolute path" {
  run push_resolved_into_pane "p-prev" "target.md" "$FIX/repo"
  [ "$status" -eq 0 ]
  [[ "$(sent)" == *"pane send-text p-prev :e $FIX/repo/target.md"* ]]
  [[ "$(sent)" == *"pane send-keys p-prev Enter"* ]]
}

@test "push_resolved_into_pane: a path:LINE token also jumps to the line" {
  run push_resolved_into_pane "p-prev" "target.md:12" "$FIX/repo"
  [ "$status" -eq 0 ]
  [[ "$(sent)" == *":e $FIX/repo/target.md"* ]]
  [[ "$(sent)" == *"12g"* ]]
}

@test "push_resolved_into_pane: no line suffix means no line jump is sent" {
  run push_resolved_into_pane "p-prev" "target.md" "$FIX/repo"
  [ "$status" -eq 0 ]
  [[ "$(sent)" != *"g"$'\n'* ]] || true
  [ "$(sent | grep -c 'send-text')" -eq 1 ]
}

# NEGATIVE CONTROL: a URL is browser work, not something `:e` can page. The
# assertion is that NOTHING was driven, which is what distinguishes a real
# refusal from a silent no-op that happens to return the same status.
@test "push_resolved_into_pane: refuses a URL and sends nothing" {
  run push_resolved_into_pane "p-prev" "https://example.com/x" "$FIX/repo"
  [ "$status" -ne 0 ]
  [ -z "$(sent)" ]
}

@test "push_resolved_into_pane: refuses an unresolvable token and sends nothing" {
  run push_resolved_into_pane "p-prev" "no-such-file-here.md" "$FIX/repo"
  [ "$status" -ne 0 ]
  [ -z "$(sent)" ]
}

@test "push_resolved_into_pane: refuses an empty pane id and sends nothing" {
  run push_resolved_into_pane "" "target.md" "$FIX/repo"
  [ "$status" -ne 0 ]
  [ -z "$(sent)" ]
}

# ---- push_into_preview (the action-context composition) ----

@test "push_into_preview: pushes when the pane is a preview" {
  run push_into_preview "p-prev" "target.md"
  [ "$status" -eq 0 ]
  [[ "$(sent)" == *":e $FIX/repo/target.md"* ]]
}

# NEGATIVE CONTROL: the whole point of the label check is that a click in an
# ordinary pane must fall through to spawning, never drive that pane's keys.
@test "push_into_preview: a non-preview pane is left alone and sends nothing" {
  run push_into_preview "p-shell" "target.md"
  [ "$status" -ne 0 ]
  [ -z "$(sent)" ]
}

# ---- emit_any ----

# glow is stubbed rather than assumed present: keying this on whether the
# host happens to have glow makes the result environment-dependent, and an
# "either 0 or 1 is fine" assertion cannot fail at all.
@test "emit_any: routes to the claiming kind's emit_ half" {
  printf '#!/usr/bin/env bash\nprintf "GLOW-EMITTED\\n"\n' > "$STUB/glow"
  chmod +x "$STUB/glow"
  run bash -c "PATH='$STUB:/usr/bin:/bin'; . '$LIB'; emit_any '$FIX/repo/target.md'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GLOW-EMITTED"* ]]
}

@test "emit_any: returns non-zero for a kind with no emit_ half" {
  # .sh is claimed by the text renderer, which deliberately has no emit_ half
  run emit_any "$FIX/repo/code.sh"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "emit_any: returns non-zero when nothing claims the path" {
  run emit_any "$FIX/repo/definitely-absent"
  [ "$status" -ne 0 ]
}

# The incident this guards: a popup-hosted preview's rename landed on the
# pane UNDERNEATH (popups are unlisted, `pane current` returns the focused
# listed pane), so agent/chat panes ended up wearing "Preview:" labels - and
# a file pick then typed ":e <path>" plus Enter straight into the user's
# chat box. The label is necessary but NOT sufficient: the pane must also
# actually be paging (foreground includes less). Fail closed.
@test "pane_is_preview: a MISLABELED agent pane (Preview label, no less) is rejected" {
  run pane_is_preview "p-mislabel"
  [ "$status" -ne 0 ]
}

@test "push_into_preview: refuses to type into a mislabeled agent pane" {
  run push_into_preview "p-mislabel" "target.md"
  [ "$status" -ne 0 ]
  [ -z "$(sent)" ]
}

@test "name_pane: QUICKLOOK_ANON_PANE=1 skips the rename RPC, keeps the footer label" {
  run bash -c ". '$LIB'; QUICKLOOK_ANON_PANE=1 name_pane 'doc.md' '$FIX/repo/target.md'; printf 'label=%s' \"\$QUICKLOOK_OBJECT_LABEL\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"label=target.md"* ]]
  ! grep -q "pane rename" "$MARKER" 2>/dev/null
}
