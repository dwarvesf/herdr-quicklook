# vhs tape: clickable links without an upstream herdr change.
# Run from a scratch checkout whose directory is named herdr-quicklook:
#   cd <scratch-parent>/herdr-quicklook && vhs demo/linkify.tape
#
# The take uses the real native plugin_action binding, real pane scan, real
# OSC-8 virtual link, and two real SGR Ctrl+clicks: first a bare path from the
# linkify overlay, then the original GitHub blob URL directly.
Output demo/linkify.gif

Require herdr
Require jq
Require bash

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 35ms

Hide
Type `cfg=/private/tmp/herdr-linkify-$RANDOM.toml; herdr --default-config > "$cfg"; printf '\n[[keys.command]]\nkey = "prefix+shift+l"\ntype = "plugin_action"\ncommand = "herdr-quicklook.linkify"\n' >> "$cfg"; LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/bin:$PATH HERDR_CONFIG_PATH="$cfg" env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV -u HERDR_PLUGIN_CONTEXT_JSON -u HERDR_PLUGIN_EVENT_JSON -u HERDR_PLUGIN_CLICKED_URL herdr --session demo-linkify-$RANDOM`
Enter
Sleep 4s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 400ms
Type "herdr plugin link . >/dev/null 2>&1 && clear"
Enter
Sleep 2s
Type `printf '\033[2J\033[H\033[7m ▶ AGENT OUTPUT: PLAIN PATHS + REPOSITORY REFERENCE \033[0m\n\n  changed  scripts/linkify-pane.sh:30\n  inspect  scripts/agent-suggest.sh:101\n  source   https://github.com/dwarvesf/herdr-quicklook/blob/main/scripts/lib.sh#L225\n\n\033[7m ⌨ PREFIX+SHIFT+L → LINKIFY \033[0m\n'`
Enter
Sleep 1.5s
Show

Sleep 2s
Ctrl+B
Sleep 400ms
Type "L"
Sleep 4s

# Ctrl+left-click scripts/linkify-pane.sh:30 in the OSC-8 link overlay.
Ctrl+[
Type@1ms "[<16;45;9M"
Ctrl+[
Type@1ms "[<16;45;9m"
Sleep 3.5s

Type "q"
Sleep 2s
Type "q"
Sleep 2s

# Ctrl+left-click the original GitHub blob URL; the narrow URL handler opens
# the local checkout at #L225 instead of falling through to the browser.
Ctrl+[
Type@1ms "[<16;45;6M"
Ctrl+[
Type@1ms "[<16;45;6m"
Sleep 3.5s

Type "q"
Sleep 2s
