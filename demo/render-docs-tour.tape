# vhs tape: the documents story - a markdown file (glow), a docx (pandoc ->
# glow), a Jupyter notebook (pandoc's ipynb reader -> glow). Run
# demo/render-anything-fixtures.sh first (writes the scratch fixtures + the
# `open` wrapper this tape types). `./open <fixture>` is a one-line wrapper
# (`exec bash <worktree>/scripts/open-preview.sh "$@"`) around the real
# production `preview` entrypoint - the SAME script the `prefix+v`
# keybinding runs, just a short relative name so the <30s budget survives
# three separate opens. Fixtures live in a neutral /private/tmp scratch dir
# (never /tmp - macOS's /tmp is a symlink and breaks repo-containment
# checks), so no internal worktree path is ever visible on screen.
#
# Run from THIS checkout (Output path is relative to vhs's own cwd):
#   ./demo/render-anything-fixtures.sh && vhs demo/render-docs-tour.tape
Output demo/render-docs-tour.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 30ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV EDITOR=vim herdr --session demo-docs-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link /Users/tieubao/workspace/tieubao/herdr-quicklook/.claude/worktrees/ql4-08 >/dev/null 2>&1 && cd /private/tmp/ql-demo-docs && clear"
Enter
Sleep 2s
Show

Sleep 800ms

# 0. scene banner
Type `printf '\033[7m ▶ documents: md · docx · ipynb \033[0m\n'`
Enter
Sleep 1s

# 1. markdown -> glow
Type "./open sample.md"
Enter
Sleep 3s
Type "q"
Sleep 800ms

# 2. docx -> pandoc -> glow
Type `printf '\033[7m ▶ docx: pandoc -> glow \033[0m\n'`
Enter
Sleep 600ms
Type "./open sample.docx"
Enter
Sleep 3s
Type "q"
Sleep 800ms

# 3. ipynb -> pandoc's ipynb reader -> glow
Type `printf '\033[7m ▶ ipynb: pandoc -> glow \033[0m\n'`
Enter
Sleep 600ms
Type "./open sample.ipynb"
Enter
Sleep 3s
Type "q"
Sleep 800ms
