#!/usr/bin/env bash
# LESSOPEN input preprocessor for every FILE-BACKED preview.
#
# less invokes this as `|render-open.sh %s` (the leading pipe is what makes
# less read our stdout instead of a temp file). We render, link, gutter and
# pad here so that less itself always opens the REAL file. That matters for
# three things which all key off less knowing the filename:
#
#   - the pager footer names the object,
#   - the o / e / D escalations expand %-codes against the current file, and
#   - less owns a file LIST, which is the push/pop stack (`:e` pushes,
#     remove-file pops). A pipe has none of these.
#
# LESSOPEN contract: exiting with NO output tells less to show the file raw,
# which is exactly the right degrade for a kind that has no emit_ half.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

target="${1:-}"
[ -n "$target" ] || exit 0
[ -f "$target" ] || exit 0

load_config

# CLICOLOR_FORCE=1: the same trick render_command_in_pager applies, and for
# the same reason. termenv-based tools (glow/glamour) drop to a NO-COLOUR
# profile the moment stdout is not a tty, even with an explicit -s style, and
# in here glow's stdout is a pipe (into linkify | pad_left |
# pad_to_pane_height). Without this a markdown preview renders structurally
# correct but monochrome: bold survives, every colour is gone. Harmless to
# bat/delta/jq, which force colour with their own flags.
export CLICOLOR_FORCE=1

# No emit_ half for this kind (an image pushed onto the stack with `:e`, say):
# produce NOTHING so less shows the file raw. Asked before the pipeline runs,
# because pad_to_pane_height would otherwise emit blank padding and less reads
# any output at all as "handled".
emit_supported "$target" || exit 0

emit_any "$target" 2>/dev/null | linkify | pad_left | pad_to_pane_height
