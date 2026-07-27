# vhs tape: the hero drill-down story - prefix+v fires the hint overlay, a
# letter opens sample.md in an ADDRESSABLE preview overlay (footer teaches
# ", back" and "prefix+v pick"), the chord fires a SECOND hint INSIDE that
# preview (it opens as a top-surface popup with the target-count banner), a
# letter PUSHES CHECKLIST.md onto the same pane's stack, `,` pops back to
# sample.md at its old position, q closes. One pane, any depth.
#
# Run demo/render-anything-fixtures.sh first (writes the
# /private/tmp/ql-demo-hint fixtures: notes.txt naming sample.md +
# sample.csv, a headed sample.md that references CHECKLIST.md, the checklist
# itself, a ~40-row sample.csv).
#
# Mechanics, learned the hard way (see demo/README.md landmines):
# - The FIRST hint invoke types the CLI form (`herdr plugin action invoke
#   hint ...`) because that is a shell prompt; the SECOND invoke happens
#   inside the preview (less owns the keys, no prompt to type at), so it
#   uses the real prefix chord - the ONE chord press of the session, which
#   is the reliable one (re-pressing a chord in one vhs session is not).
# - Hint LETTERS are position-dependent. Beat-A's `s` for sample.md was
#   read off the recorded overlay frame (ffmpeg frame-dump); beat-B's `a`
#   for CHECKLIST.md was computed offline by replaying the exact pipeline
#   (render-open.sh -> ansi-strip -> strip_pager_footer -> pick_scan_text).
#   Re-verify both against the live overlay frame before trusting a re-cut.
# - vhs has no mouse primitive: Ctrl+click-pushes are stated on screen by
#   the end banner, never faked.
#
# Run from THIS checkout (Output path is relative to vhs's own cwd):
#   ./demo/render-anything-fixtures.sh && vhs demo/hint-flow-tour.tape
Output demo/hint-flow-tour.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 30ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV EDITOR=vim herdr --session demo-hint-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link /Users/tieubao/workspace/tieubao/herdr-quicklook >/dev/null 2>&1 && cd /private/tmp/ql-demo-hint && clear"
Enter
Sleep 2s
Show

Sleep 300ms

# 0. scene banner + the fixture pane: two openable tokens in plain prose
Type `printf '\033[7m ▶ prefix+v: hints land on everything openable \033[0m\n'`
Enter
Sleep 700ms
Type "cat notes.txt"
Enter
Sleep 800ms

# 1. fire the hint overlay - the same entrypoint prefix+v dispatches (fast
# type: the CLI invocation is a mechanical workaround, not story content).
# The bottom row is the overlay's own banner: "hint · N target(s) · ...".
Set TypingSpeed 8ms
Type "herdr plugin action invoke hint --plugin herdr-quicklook >/dev/null 2>&1"
Set TypingSpeed 30ms
Enter
Sleep 2s
Sleep 1.5s

# 2. pick sample.md by its hint letter (s) -> it opens in an ADDRESSABLE
# preview overlay; the footer teaches the stack: ", back" and "prefix+v pick".
# (Letter re-verified from the recorded frame: d=notes.txt s=sample.md
# a=sample.csv on this screen.)
Type "s"
Sleep 2.5s
Sleep 1.5s

# 3. the drill-down: fire the hint AGAIN, from INSIDE the preview, with the
# real prefix chord. The hint opens as a top-surface popup over the preview,
# banner counting the targets found IN the rendered document.
Ctrl+B
Sleep 400ms
Type "v"
Sleep 2s
Sleep 1.5s

# 4. pick CHECKLIST.md by its letter (a) -> PUSHED onto the SAME pane's
# stack (no new window): the preview now shows the checklist, whose last
# line says how to get back.
Type "a"
Sleep 2.5s
Sleep 2s

# 5. pop: `,` returns to sample.md, same pane, same scroll position
Type ","
Sleep 2.5s

# 6. close the whole stack
Type "q"
Sleep 600ms

# 7. end banner: the affordances this take could not show as keystrokes
Type `printf '\033[7m ▶ Ctrl+click a path: same push · , pops · UPPERCASE letter: full tab \033[0m\n'`
Enter
Sleep 900ms
Type `printf '\033[7m ▶ o = file-viewer · e = editor · D = diff \033[0m\n'`
Enter
Sleep 1.2s

Hide
Type "exit"
Enter
Sleep 500ms
