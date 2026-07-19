# vhs tape: the images story - png (chafa ANSI), gif (chafa, a REAL
# multi-frame animation), svg (rsvg-convert -> chafa), pdf (page-1 poster +
# extracted text). `./open <fixture>` is a one-line wrapper
# (`exec bash <worktree>/scripts/open-preview.sh "$@"`, written by
# render-anything-fixtures.sh) around the real production `preview`
# entrypoint - the SAME script the `prefix+v` keybinding runs, just a short
# relative name so the recording survives four separate opens without
# eating the budget on typing a long absolute path four times. Fixtures live
# in a neutral /private/tmp scratch dir (never /tmp - macOS's /tmp is a
# symlink and breaks repo-containment checks), so no internal worktree path
# is ever visible on screen.
#
# Every `./open` beat holds a 3.5-4s open+paint delay (the overlay pane has
# to spawn and the renderer has to run before anything is on screen) THEN a
# 2s+ hold of the rendered content before closing - the actual render is the
# money shot, not the typed command. gif fixture note: sample.gif is a real
# 8-frame animated gif (render-anything-fixtures.sh); #35 (97bc94d) fixed
# gif.sh's chafa invocation to `--animate=on` (chafa 1.18.2 needs an
# explicit =BOOL) plus a real wall-clock kill bound, so
# QUICKLOOK_GIF_ANIMATE_DURATION=4 on the session launch line below keeps
# the animate beat's play-through inside this tour's time budget.
#
# Run from THIS checkout (Output path is relative to vhs's own cwd):
#   ./demo/render-anything-fixtures.sh && vhs demo/render-images-tour.tape
Output demo/render-images-tour.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 15ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 QUICKLOOK_GIF_ANIMATE_DURATION=4 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV EDITOR=vim herdr --session demo-images-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link /Users/tieubao/workspace/tieubao/herdr-quicklook/.claude/worktrees/ql4-08 >/dev/null 2>&1 && cd /private/tmp/ql-demo-images && clear"
Enter
Sleep 2s
Show

Sleep 500ms

# 0. scene banner
Type `printf '\033[7m ▶ images: png · gif · svg · pdf \033[0m\n'`
Enter
Sleep 700ms

# 1. png -> chafa inline ANSI art
Type "./open sample.png"
Enter
Sleep 4s
Sleep 2.5s
Type " "
Sleep 600ms

# 2. gif -> chafa (real animated multi-frame gif; see the header note)
Type `printf '\033[7m ▶ gif: chafa \033[0m\n'`
Enter
Sleep 400ms
Type "./open sample.gif"
Enter
Sleep 4s
Sleep 2.5s
Type " "
Sleep 600ms

# 3. svg -> rsvg-convert -> the SAME chafa path
Type `printf '\033[7m ▶ svg: rsvg-convert -> chafa \033[0m\n'`
Enter
Sleep 400ms
Type "./open sample.svg"
Enter
Sleep 4s
Sleep 2.5s
Type " "
Sleep 600ms

# 4. pdf -> page-1 poster (the money shot; text sub-beat dropped to stay
# in budget - it still opens after the poster closes, so it still needs a
# quick close, just no dedicated hold)
Type `printf '\033[7m ▶ pdf: page-1 poster + extracted text \033[0m\n'`
Enter
Sleep 400ms
Type "./open sample.pdf"
Enter
Sleep 4s
Sleep 2.5s
Type " "
Sleep 700ms
Type "q"
Sleep 600ms
