# vhs tape: a tour of every token kind herdr-quicklook dispatches on -
# a plain path, a GitHub blob URL (opens the LOCAL file), a bare commit SHA
# (git show), a PR reference (gh pr view), and a directory (eza --tree).
# Run from a scratch checkout so relative paths + `gh pr view` resolve
# against the real dwarvesf/herdr-quicklook repo:
#   cd <scratch-checkout> && vhs demo/tokens-tour.tape
#
# Only the FIRST open uses the real prefix+v keybinding; each subsequent one
# in this same session runs `herdr plugin action invoke preview` directly
# instead (its own JSON reply redirected away). Re-pressing prefix+v a
# second time in one vhs-driven session did not reliably reopen the overlay
# (empirically confirmed: the same keystrokes worked every time over the
# socket API but not when replayed through vhs's pty a second time) - the
# CLI form is the same production entrypoint the keybinding itself runs, so
# nothing about the demoed behavior is faked. Sleeps are generous (3.5s to
# view, 2.5s to settle after closing) since command-mode opens (git show,
# gh pr view) spin up a subprocess before the pane renders. See DECISIONS.md.
Output demo/tokens-tour.gif

Set FontSize 15
Set Width 1400
Set Height 800
Set Padding 12
Set TypingSpeed 45ms

Hide
Type "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 env -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV herdr --session demo-tokens-$RANDOM"
Enter
Sleep 3.5s
Type "setopt nocorrect 2>/dev/null"
Enter
Sleep 500ms
Type "herdr plugin link . >/dev/null 2>&1 && clear"
Enter
Sleep 2s
Show

Sleep 1s

# 1. a plain relative path - the real prefix+v keybinding
Type `printf '%s' "README.md" | pbcopy`
Enter
Sleep 800ms
Ctrl+B
Sleep 500ms
Type "v"
Sleep 3.5s
Type "q"
Sleep 2.5s

# 2. a GitHub blob URL -> opens the SAME file, locally, at the line
Type `printf '%s' "https://github.com/dwarvesf/herdr-quicklook/blob/main/scripts/lib.sh#L1" | pbcopy && herdr plugin action invoke preview --plugin herdr-quicklook >/dev/null 2>&1`
Enter
Sleep 3.5s
Type "q"
Sleep 2.5s

# 3. a bare commit SHA -> git show, paged
Type `printf '%s' "5a69baa" | pbcopy && herdr plugin action invoke preview --plugin herdr-quicklook >/dev/null 2>&1`
Enter
Sleep 3.5s
Type "q"
Sleep 2.5s

# 4. a PR reference -> gh pr view, paged
Type `printf '%s' "#7" | pbcopy && herdr plugin action invoke preview --plugin herdr-quicklook >/dev/null 2>&1`
Enter
Sleep 3.5s
Type "q"
Sleep 2.5s

# 5. a directory -> eza --tree (herdr-file-viewer not linked in this take)
Type `printf '%s' "scripts/handlers" | pbcopy && herdr plugin action invoke preview --plugin herdr-quicklook >/dev/null 2>&1`
Enter
Sleep 3.5s
Type "q"
Sleep 1s
