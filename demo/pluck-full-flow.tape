Output demo/pluck-full-flow.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type "cd /private/tmp/demo/herdr-quicklook && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-pluck-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link . >/dev/null 2>&1 && herdr plugin link ~/.config/herdr/plugins/github/rmarganti.herdr-pluck-* >/dev/null 2>&1 && clear"
Enter
Sleep 2s
Show

Sleep 1s
# A pane with several kinds of links on screen at once, agent-log flavor.
Type `printf '%s\n' "docs:    README.md" "config:  DESIGN.md" "commit:  5a69baa" "PR:      #7"`
Enter
Sleep 1.5s

# The one-key chain: pluck's hint overlay appears, pick a token, and
# quicklook opens it immediately - no separate keypress to consume the pick.
Type "herdr plugin action invoke pluck-chain --plugin herdr-quicklook >/dev/null 2>&1"
Enter
Sleep 3s
Type "s"
Sleep 4s
Type "q"
Sleep 1s
