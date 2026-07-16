# vhs tape: the open-in-viewer demo. Needs the herdr-file-viewer plugin on
# this host. Run from a repo checkout: vhs demo/viewer.tape
Output demo/viewer.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type `printf '%s' "tools/herdr-deploy/README.md:49" | pbcopy`
Enter
Sleep 500ms
Type "env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-"
Enter
Sleep 3.5s
Show

Sleep 1.5s
Ctrl+B
Sleep 400ms
Type "o"
Sleep 4s
Down
Sleep 500ms
Down
Sleep 2s
