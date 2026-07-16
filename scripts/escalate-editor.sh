#!/usr/bin/env bash
# escalate-editor.sh: invoked by less as a lesskey `pshell` command when the
# user presses `e` in the quick-look overlay. less calls it as
# `escalate-editor.sh [+LINE] FILE` (the same +LINE/FILE shape LESSEDIT
# passes to `visual`, reusing escalate.sh's arg-parsing convention).
#
# Unlike escalate.sh (bound to the single `visual` slot, already claimed by
# `o` -> herdr-file-viewer), `e` cannot reuse `visual`. It is instead bound
# directly to less's `pshell` action (the `#` shell-escape, prompt-expanded)
# via an extra string in lesskey, so this script runs as an ordinary
# shell-escape command. less already suspends/resumes itself around a
# shell-escape: it does NOT need this script to kill its parent (contrast
# escalate.sh, which does, because `visual` hands off the whole session).
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

load_config

line=""
file=""
for a in "$@"; do
  case "$a" in
    +[0-9]*) line="${a#+}" ;;
    *) file="$a" ;;
  esac
done
[ -z "$file" ] && exit 0

# Precedence: config QUICKLOOK_EDITOR (from .env, see load_config) > $EDITOR
# > "zed --wait". A config value beats $EDITOR because the herdr server
# process that launches this pane does not reliably inherit an interactive
# shell's exported EDITOR (the same server-env gotcha QUICKLOOK_ROOTS exists
# for); the .env file is read directly regardless of the server's env.
editor_cmd=()
read -ra editor_cmd <<<"${QUICKLOOK_EDITOR:-${EDITOR:-zed --wait}}"
[ "${#editor_cmd[@]}" -eq 0 ] && exit 0

if [ -n "$line" ]; then
  exec "${editor_cmd[@]}" "+$line" "$file"
else
  exec "${editor_cmd[@]}" "$file"
fi
