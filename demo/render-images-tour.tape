# vhs tape: the images story - png (chafa ANSI), gif (chafa, still-frame -
# see the note below), svg (rsvg-convert -> chafa), pdf (page-1 poster +
# extracted text). One pass, <30s. `./open <fixture>` is a one-line wrapper
# (`exec bash <worktree>/scripts/open-preview.sh "$@"`, written by
# render-anything-fixtures.sh) around the real production `preview`
# entrypoint - the SAME script the `prefix+v` keybinding runs, just a short
# relative name so the <30s budget survives four separate opens without
# eating it on typing a long absolute path four times. Fixtures live in a
# neutral /private/tmp scratch dir (never /tmp - macOS's /tmp is a symlink
# and breaks repo-containment checks), so no internal worktree path is ever
# visible on screen.
#
# gif fixture note: sample.gif is a SINGLE-FRAME gif, not a real animation.
# chafa 1.18.2 (installed here) requires `--animate=BOOL`; gif.sh's shipped
# `chafa --animate -d N -- <path>` mis-parses "-d" as --animate's value and
# errors, falling through to its own fallback `chafa --format symbols --
# <path>` with no --animate/-d at all - which, on a genuinely multi-frame
# gif, free-runs forever in a real TTY (chafa defaults --animate to on and
# an unset duration to infinite for an animation; confirmed live via the
# herdr socket API, not just this recording). A single-frame fixture takes
# the same render_gif code path but has nothing to loop, so it closes on
# the normal "press any key" prompt like every other still render. Real,
# worth-flagging renderer-side finding (out of scope for this docs/demo
# sub-goal); see render-anything-fixtures.sh's own comment and the PR body.
#
# Run from THIS checkout (Output path is relative to vhs's own cwd):
#   ./demo/render-anything-fixtures.sh && vhs demo/render-images-tour.tape
Output demo/render-images-tour.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 30ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV EDITOR=vim herdr --session demo-images-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link /Users/tieubao/workspace/tieubao/herdr-quicklook/.claude/worktrees/ql4-08 >/dev/null 2>&1 && cd /private/tmp/ql-demo-images && clear"
Enter
Sleep 2s
Show

Sleep 800ms

# 0. scene banner
Type `printf '\033[7m ▶ images: png · gif · svg · pdf \033[0m\n'`
Enter
Sleep 1s

# 1. png -> chafa inline ANSI art
Type "./open sample.png"
Enter
Sleep 2.5s
Type "q"
Sleep 800ms

# 2. gif -> chafa (still-frame; see the header note)
Type `printf '\033[7m ▶ gif: chafa \033[0m\n'`
Enter
Sleep 600ms
Type "./open sample.gif"
Enter
Sleep 2.5s
Type "q"
Sleep 800ms

# 3. svg -> rsvg-convert -> the SAME chafa path
Type `printf '\033[7m ▶ svg: rsvg-convert -> chafa \033[0m\n'`
Enter
Sleep 600ms
Type "./open sample.svg"
Enter
Sleep 2.5s
Type "q"
Sleep 800ms

# 4. pdf -> page-1 poster, then the extracted text
Type `printf '\033[7m ▶ pdf: page-1 poster + extracted text \033[0m\n'`
Enter
Sleep 600ms
Type "./open sample.pdf"
Enter
Sleep 2.5s
Type "q"
Sleep 400ms
Type "q"
Sleep 800ms
