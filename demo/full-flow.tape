# vhs tape: the full loop with several link types on screen at once.
# Needs the herdr-pluck plugin (Vimium-style hint labels) installed on this
# host, bound to prefix+y. Run from a repo checkout: vhs demo/full-flow.tape
Output demo/full-flow.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type "env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-$RANDOM"
Enter
Sleep 3.5s
# A pane with many kinds of links on screen at once
Type `printf '%s\n' "docs:    src/server/handler.go:142" "config:  ~/.config/app/config.toml" "PR:      https://github.com/dwarvesf/herdr-quicklook/pull/1" "just a name:  CHANGELOG.md"`
Enter
Sleep 1s
Show

Sleep 1.5s
# pluck: hint labels appear over every token, Vimium-style; pick the first path
Ctrl+B
Sleep 400ms
Type "y"
Sleep 2s
Type "a"
Sleep 1s
# quick-look it
Ctrl+B
Sleep 400ms
Type "v"
Sleep 3.5s
Type "q"
Sleep 1.5s
