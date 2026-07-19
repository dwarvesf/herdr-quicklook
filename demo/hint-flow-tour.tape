# vhs tape: the hero hint-flow story - prefix+v fires the hint overlay, a
# hinted token is picked by LETTER (twice: sample.md then sample.csv), each
# opens in herdr's 90% popup. Run demo/render-anything-fixtures.sh first
# (writes the /private/tmp/ql-demo-hint scratch fixtures this tape records
# against: notes.txt mentioning sample.md + sample.csv, a headed sample.md,
# a ~40-row sample.csv so d/u half-page scroll visibly moves it).
#
# Only the FIRST hint invoke uses the real `herdr plugin action invoke hint
# --plugin herdr-quicklook` command typed directly - the exact entrypoint
# prefix+v itself dispatches (same precedent as tokens-tour.tape's second+
# opens: re-pressing a prefix chord a second time in one vhs-driven session
# does not reliably re-fire, so every invoke in this tape uses the CLI form,
# not Ctrl+B v). vhs has no mouse-click primitive, so the "or a plain mouse
# click" beat presses the hint letter of sample.csv instead of clicking it -
# the banner states the click affordance on screen, it is never faked.
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
Type "herdr plugin link /Users/tieubao/workspace/tieubao/herdr-quicklook/.claude/worktrees/ql4-08 >/dev/null 2>&1 && cd /private/tmp/ql-demo-hint && clear"
Enter
Sleep 2s
Show

Sleep 500ms

# 0. scene banner + the fixture pane: two openable tokens in plain prose
Type `printf '\033[7m ▶ prefix+v: hints land on everything openable \033[0m\n'`
Enter
Sleep 700ms
Type "cat notes.txt"
Enter
Sleep 1.2s

# 1. fire the hint overlay - the same entrypoint prefix+v dispatches
Type "herdr plugin action invoke hint --plugin herdr-quicklook >/dev/null 2>&1"
Enter
Sleep 2s
Sleep 1.2s

# 2. pick sample.md by its hint letter (d) -> popup opens, glow renders
Type "d"
Sleep 2s
Sleep 1.2s
Type "q"
Sleep 300ms

# 3. second beat: pick by letter, or a plain click (vhs cannot synthesize
# a real mouse click - the affordance is stated on screen, not faked)
Type `printf '\033[7m ▶ pick by letter - or a plain mouse click \033[0m\n'`
Enter
Sleep 500ms
Type "herdr plugin action invoke hint --plugin herdr-quicklook >/dev/null 2>&1"
Enter
Sleep 2s
Sleep 900ms

# sample.csv's hint letter (s) -> popup opens, qsv table renders
Type "s"
Sleep 2s
Sleep 1.2s

# d/u half-page scroll, visible against the ~40-row table
Type "d"
Sleep 700ms
Type "u"
Sleep 700ms
Type "q"
Sleep 300ms

# 4. end banner: the escalation keys inside any popup
Type `printf '\033[7m ▶ o = file-viewer · e = editor · D = diff \033[0m\n'`
Enter
Sleep 1s
