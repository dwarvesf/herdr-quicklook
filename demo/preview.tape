# vhs tape: the preview overlay demo. Run from a repo checkout so the
# relative path on the clipboard resolves. Records a REAL herdr session.
#   cd <repo> && vhs demo/preview.tape
Output demo/preview.gif

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
Type "v"
Sleep 3s
Down
Sleep 500ms
Down
Sleep 500ms
Down
Sleep 1.5s
Type "q"
Sleep 1.5s
