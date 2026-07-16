# shellcheck shell=bash
# vcs.sh: STUB for SG-02 (vcs-tokens). Reserved shape: a bare commit SHA ->
# `git show`, a `#123`/PR reference -> `gh pr view`, render-mode `command`
# (see the RESOLVED_CMD contract note at the top of lib.sh - untrusted
# clipboard input must stay a real argv, never a rebuilt string). Registered
# in HANDLER_KINDS now, ahead of path.sh's catch-all, so SG-02 only needs to
# edit this file: a real match_vcs + handle_vcs body, no lib.sh or
# pane-script changes required.

match_vcs() { return 1; }
handle_vcs() { return 1; }
