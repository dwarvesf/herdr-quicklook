# vhs tape: the quick-look demo. Run from a repo checkout so the relative
# path resolves. Records a REAL herdr session:
#   agent-style output with a path on screen -> copy it -> prefix+v pops it.
#   cd <repo> && vhs demo/preview.tape
Output demo/preview.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type "env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-$RANDOM"
Enter
Sleep 3.5s
Show

# The situation: an agent just printed a file path you want to look at
Type `printf '%s\n' "agent: reconnect logic patched, notes updated" "  see: tools/herdr-deploy/README.md:49" "  PR:  https://github.com/dwarvesf/herdr-quicklook"`
Enter
Sleep 2s

# Copy the path (a hint plugin like herdr-pluck does this with one keystroke)
Type `printf '%s' "tools/herdr-deploy/README.md:49" | pbcopy`
Enter
Sleep 1.5s

# Quick-look it: prefix+v pops the file at line 49
Ctrl+B
Sleep 400ms
Type "v"
Sleep 3s
Down
Sleep 500ms
Down
Sleep 1.5s
Type "q"
Sleep 1.5s
