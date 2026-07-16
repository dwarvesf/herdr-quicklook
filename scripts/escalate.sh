#!/usr/bin/env bash
# escalate.sh: invoked by less as $VISUAL when the user presses `o` (or `v`)
# in the quick-look overlay. less calls it as `escalate.sh [+LINE] FILE`
# (the default LESSEDIT prototype). Hands the file to the open-in-viewer
# action, then closes the overlay by ending the parent less.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

line=""
file=""
for a in "$@"; do
  case "$a" in
    +[0-9]*) line="${a#+}" ;;
    *) file="$a" ;;
  esac
done
[ -z "$file" ] && exit 0

# Pass the ACTUAL on-screen file explicitly. `env -u QUICKLOOK_TOKEN` stops
# open-in-viewer's pick_token from re-reading the inherited env token (which
# would re-resolve the original token, not the file the user scrolled to).
env -u QUICKLOOK_TOKEN bash "$script_dir/open-in-viewer.sh" "${file}${line:+:$line}"

# Close the overlay: this script's parent is the less holding the popup open.
kill -TERM "$PPID" 2>/dev/null
exit 0
