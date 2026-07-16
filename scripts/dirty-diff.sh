#!/usr/bin/env bash
# dirty-diff.sh: invoked by less as a lesskey `shell` command when the user
# presses `d` in the quick-look overlay (see ../lesskey). less expands the
# bare `%` (the `shell` action's own filename token, distinct from pshell's
# two-char `%g`) to the current filename before typing the extra string in;
# verified empirically (real less session, PR proof) to arrive as exactly
# ONE argv element even with a space in the name, the same injection
# posture escalate-editor.sh relies on %g for with `e`.
#
# `d` is the THIRD, still-distinct less action used for shelling out here:
# `o` claims the single `visual` slot, `e` claims `pshell` (see
# DECISIONS.md, "SG-06 editor-escalate: `e` key mechanism"). `d` claims
# `shell` (the default `!` slot) instead of adding a second `pshell`
# binding, so the three in-popup escape hatches never share one action's
# single extra-string.
#
# A dirty file opens a NESTED less: `git diff` piped through delta when
# installed, else git's own --color=always rendering piped straight into
# less -R (the "delta/less-colored" degrade the goal calls for). The nested
# pager gets a purpose-built temp lesskey where q, Esc-Esc AND d all quit,
# so pressing `d` again inside the diff view is the toggle back, same as
# pressing `q`. Quitting hands control back to this script, which exits,
# and the `\020` (^P) prefix on the outer lesskey binding (see ../lesskey)
# suppresses the "(press RETURN)" prompt so resuming the file view feels
# like `e`'s editor round-trip. A clean file has nothing to nest a pager
# around, so it prints a one-line notice and waits for its own keypress
# instead (a nested pager would have nothing to show).
#
# No env var wiring needed from preview-pane.sh: QUICKLOOK_EDITOR_SCRIPT is
# already exported there (for `e`) and points at a sibling script in this
# same scripts/ directory, so ../lesskey derives this script's own path
# from it instead of preview-pane.sh growing a QUICKLOOK_DIRTY_DIFF_SCRIPT
# export (out of this sub-goal's scope edges).
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$script_dir/lib.sh"

load_config

file="${1:-}"
[ -z "$file" ] && exit 0

repo_dir="$(dirname "$file")"
diff_output="$(git -C "$repo_dir" diff --color=always -- "$file" 2>/dev/null)"

if [ -z "$diff_output" ]; then
  printf 'quicklook: no unstaged changes for %s\n' "$file"
  # Same pause pattern as preview-pane.sh's pause_close(): plain stdin, no
  # explicit /dev/tty (that would block forever with no controlling
  # terminal, e.g. under a test harness); a closed/non-tty stdin fails the
  # read immediately and the sleep gives a bounded, non-interactive pause
  # instead of no pause at all.
  read -r -n1 -p "(press any key to continue) " _ 2>/dev/null || sleep 2
  exit 0
fi

diff_lesskey="$(mktemp)"
trap 'rm -f "$diff_lesskey"' EXIT
cat >"$diff_lesskey" <<'LESSKEY'
#command
\e\e quit
q quit
d quit
LESSKEY

if command -v delta >/dev/null 2>&1; then
  printf '%s\n' "$diff_output" | delta --paging=never | less -R --lesskey-src="$diff_lesskey"
else
  printf '%s\n' "$diff_output" | less -R --lesskey-src="$diff_lesskey"
fi
