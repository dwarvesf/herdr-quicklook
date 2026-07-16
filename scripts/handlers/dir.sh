# shellcheck shell=bash
# dir.sh: STUB for SG-04 (dir-targets). Reserved shape: a token that resolves
# to a directory opens the file-viewer rooted there (render-mode `viewer`),
# or an eza/ls tree in the popup when the viewer is absent (render-mode
# `command`). Registered in HANDLER_KINDS now, ahead of path.sh's catch-all,
# so SG-04 only needs to edit this file: a real match_dir + handle_dir body,
# no lib.sh or pane-script changes required. Must test file first, dir
# second, so it never shadows path.sh's file resolution.

match_dir() { return 1; }
handle_dir() { return 1; }
