# vhs tape: pick-anywhere (v0.5), the NEGATIVE CONTROL , an empty pane and
# an empty clipboard, proving `pick` reports an honest empty state instead
# of a crash or a silent no-op. Run from a scratch checkout:
#   cd <scratch-checkout> && vhs demo/pick-anywhere-empty.tape
#
# Same real prefix+v -> pluck-chain -> (herdr-pluck absent) -> pick reroute
# as pick-anywhere-main.tape; concatenated onto that take with gifsicle to
# form the single committed demo/pick-anywhere.gif (see demo/README.md).
Output demo/pick-anywhere-empty.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-pickneg-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "printf '' | pbcopy"
Enter
Sleep 300ms
Type "herdr plugin link . >/dev/null 2>&1 && clear"
Enter
Sleep 2s
Show

Sleep 500ms
Type `printf '\033[7m \xe2\x96\xb6 negative control: empty pane, empty clipboard \033[0m\n'`
Enter
Sleep 800ms
Type `printf '\033[7m \xe2\x8c\xa8 prefix+v -> pick anywhere \033[0m\n'`
Enter
Sleep 800ms
Type "clear"
Enter
Sleep 800ms

Ctrl+B
Sleep 500ms
Type "v"
Sleep 3.5s
