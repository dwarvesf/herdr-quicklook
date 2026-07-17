Output demo/clip-o.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type "cd /private/tmp/demo/herdr-quicklook && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-o-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link . >/dev/null 2>&1 && herdr plugin link ~/.config/herdr/plugins/github/herdr-file-viewer-* >/dev/null 2>&1 && clear"
Enter
Sleep 2s
Show

Sleep 1s
Type `printf '%s' "scripts/lib.sh" | pbcopy && herdr plugin action invoke preview --plugin herdr-quicklook >/dev/null 2>&1`
Enter
Sleep 4s
Type "o"
Sleep 2s
Enter
Sleep 3s
