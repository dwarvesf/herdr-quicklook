# vhs tape: pick-anywhere (v0.5), the main take , a busy screen scanned,
# ranked, picked, opened. Run from a scratch checkout so relative paths
# resolve against the real repo:
#   cd <scratch-checkout> && vhs demo/pick-anywhere-main.tape
#
# Uses the REAL prefix+v keybinding, unmodified. Han's shipped config binds
# prefix+v to `pluck-chain` (see README's Install section); herdr-pluck is
# NOT linked into this fresh session (only herdr-quicklook is), so
# pluck-chain's own soft-dependency check (scripts/pluck-chain.sh) reroutes
# straight into the native `pick` action , the exact production fallback
# path a user with only herdr-quicklook installed hits every time, not a
# synthetic shortcut. See DECISIONS.md (SG-04) for why this is authentic.
Output demo/pick-anywhere-main.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-pick-$RANDOM"
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
Type `printf '\033[7m \xe2\x96\xb6 a busy pane: recent commits, ls, a URL \033[0m\n'`
Enter
Sleep 800ms

Type "git --no-pager log --oneline -3"
Enter
Sleep 1s
Type "ls"
Enter
Sleep 1.2s
Type `printf '%s\n' "https://github.com/dwarvesf/herdr-quicklook"`
Enter
Sleep 1.5s

Type `printf '\033[7m \xe2\x8c\xa8 prefix+v -> pick anywhere \033[0m\n'`
Enter
Sleep 800ms
Ctrl+B
Sleep 500ms
Type "v"
Sleep 3.5s

Down
Sleep 700ms
Down
Sleep 700ms
Enter
Sleep 3.5s
Type "q"
Sleep 2s
