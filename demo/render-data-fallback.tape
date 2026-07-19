# vhs tape: the data + guard story - a csv (qsv table), a minified json
# (jq), a sqlite schema (sqlite3 -readonly, table list + DDL, never a row
# dump), and an unknown/corrupt file hitting the always-on fallback (file(1)
# + hexyl dump + an install hint) - the NEGATIVE CONTROL frame for the whole
# render registry. Run demo/render-anything-fixtures.sh first (writes the
# scratch fixtures + the `open` wrapper this tape types, including
# mystery.ipynb: the first 800 bytes of /bin/ls, real binary data wearing a
# familiar extension). ipynb.sh's own binary-encoding guard declines it, the
# text renderer declines it for the same reason, and it falls all the way to
# the catch-all guard - proving a corrupt/misleading file can never reach a
# formatter, only the safe hexdump path. `./open <fixture>` is a one-line
# wrapper around the real production `preview` entrypoint. Fixtures live in
# a neutral /private/tmp scratch dir (never /tmp), so no internal worktree
# path is ever visible on screen.
#
# Every `./open` beat holds a 3.5-4s open+paint delay (the overlay pane has
# to spawn and the renderer has to run before anything is on screen) THEN a
# 2s+ hold of the rendered content before closing (`q`, every renderer here
# is paged) - the actual render is the money shot, not the typed command.
#
# Run from THIS checkout (Output path is relative to vhs's own cwd):
#   ./demo/render-anything-fixtures.sh && vhs demo/render-data-fallback.tape
Output demo/render-data-fallback.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 15ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV EDITOR=vim herdr --session demo-data-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link /Users/tieubao/workspace/tieubao/herdr-quicklook/.claude/worktrees/ql4-08 >/dev/null 2>&1 && cd /private/tmp/ql-demo-data && clear"
Enter
Sleep 2s
Show

Sleep 500ms

# 0. scene banner
Type `printf '\033[7m ▶ data + the guard: csv · json · sqlite · unknown binary \033[0m\n'`
Enter
Sleep 700ms

# 1. csv -> qsv table
Type "./open sample.csv"
Enter
Sleep 4s
Sleep 2.5s
Type "q"
Sleep 600ms

# 2. minified json -> jq .
Type `printf '\033[7m ▶ json: jq . (pretty-printed) \033[0m\n'`
Enter
Sleep 400ms
Type "./open sample.json"
Enter
Sleep 4s
Sleep 2.5s
Type "q"
Sleep 600ms

# 3. sqlite -> table list + schema, never a row dump
Type `printf '\033[7m ▶ sqlite: table list + schema (never a row dump) \033[0m\n'`
Enter
Sleep 400ms
Type "./open sample.db"
Enter
Sleep 4s
Sleep 2.5s
Type "q"
Sleep 600ms

# 4. unknown/corrupt binary -> the always-on fallback guard (NEGATIVE CONTROL)
Type `printf '\033[7m ▶ unknown binary: file(1) + hexyl + install hint \033[0m\n'`
Enter
Sleep 400ms
Type "./open mystery.ipynb"
Enter
Sleep 4s
Sleep 2.5s
Type "q"
Sleep 600ms
