# DESIGN.md

Architecture of herdr-quicklook: how a clipboard token turns into a rendered
file, a browser tab, or a paged command. User-facing behavior lives in
[README.md](README.md); this is the "how", for anyone extending it.

## Token flow

Every token-opening path (`preview`, `open-in-viewer`, `recents`, the `hint`
picker, direct URL clicks, and agent suggestions) eventually reaches
`resolve_any_token` in `scripts/lib.sh`. Clipboard-oriented actions call
`pick_token` first; the hint picker reuses `pick_scan_text` to extract
ranked candidates before handing one raw token to the same resolver. See
[Hint picker](#hint-picker) for the scan-time path.

```
$QUICKLOOK_TOKEN env / script arg / clipboard
                │
                ▼
          pick_token()
                │
                ▼
     resolve_any_token(raw)
                │
                ▼
  walk HANDLER_KINDS: github -> vcs -> url -> dir -> path
                │
    ┌───────────┼────────────┬────────────┬──────────────────┐
    ▼           ▼            ▼            ▼                  ▼
match_github  match_vcs    match_url    match_dir     match_path (catch-all)
    │           │            │            │                  │
    ▼           ▼            ▼            ▼                  ▼
github.sh     vcs.sh       url.sh       dir.sh            path.sh
(GitHub /     (SHA /       (any other   (a directory,     (filesystem path,
 GitLab /      #123 /       http(s)://)  not a file)        optional :line)
 Bitbucket     PR URL)
 blob URLs)
    │           │            │            │                  │
    └───────────┴────────────┴────────────┴──────────────────┘
                              │
                              ▼
          RESOLVED_TARGET / RESOLVED_LINE / RESOLVED_MODE / RESOLVED_CMD
                              │
                              ▼
              pane script's RESOLVED_MODE case
                              │
      ┌───────────────┬───────────────────┬────────────────────┐
      ▼                ▼                   ▼                    ▼
    file            browser             command               viewer
  less renders    url_open() ->     render_command_in_pager  herdr-file-viewer
  the file (bat    default browser  RESOLVED_CMD              pane, or an
  as LESSOPEN)                      (git show / gh pr view /  eza/ls tree
                                     eza --tree)                degrade

  resolve_any_token rc 1: no handler matched (preview-pane.sh only)
                              │
                              ▼
                     handle_bare_name()
              fuzzy git-ls-files + fzf pick
```

`resolve_any_token` returns 1 only when a `path`-shaped token's `resolve()`
can't find a file anywhere (github/url/vcs/dir always resolve one way or
another: worst case `github.sh`/`url.sh` fall back to `browser` mode). Only
`preview-pane.sh` has a TTY to run an interactive fzf pick in, so the
bare-name fallback is opt-in and called directly there, never wired into
`HANDLER_KINDS`: wiring it into the registry would have changed
`open-in-viewer.sh`'s behavior too, which never had the fuzzy fallback
before this architecture existed.

## Handler registry

A token *kind* lives entirely in one file, `scripts/handlers/<kind>.sh`,
and exports exactly two functions:

```sh
match_<kind> <raw>    # rc 0 if this handler owns the token's shape.
                      # No resolution work, no side effects.
handle_<kind> <raw>   # resolves the token. On success sets RESOLVED_TARGET /
                      # RESOLVED_LINE / RESOLVED_MODE (+ RESOLVED_CMD for
                      # command mode) and returns 0. Returns 1 if it owns the
                      # shape but couldn't resolve a target.
```

`scripts/lib.sh` auto-sources every `scripts/handlers/*.sh` at source time
(a glob loop), so a new kind never touches the sourcing mechanism, only
`HANDLER_KINDS` and the new file:

```sh
HANDLER_KINDS=(github vcs url dir path)
```

**Order matters.** `resolve_any_token` walks the array and dispatches to the
first `match_<kind>` that accepts the token. Two rules keep that safe:

- `path` is the catch-all (`match_path` always returns 0) and **must stay
  last**, or every later-registered kind becomes dead code.
- A more specific, host-aware kind checks before a generic one. `vcs` sits
  before `url` because a GitHub PR URL (`https://github.com/o/r/pull/42`)
  structurally also matches `url.sh`'s generic `http(s)://` predicate; if
  `url` were checked first it would claim every PR URL for the browser
  before `vcs` ever got a look.

### RESOLVED_MODE: the four render shapes

| Mode | Meaning | Set by | Pane-script behavior |
|---|---|---|---|
| `file` | `RESOLVED_TARGET` is a local path (`RESOLVED_LINE` optional) | `github.sh`, `path.sh` | rendered/driven directly |
| `browser` | `RESOLVED_TARGET` is a URL | `github.sh` (no local checkout), `url.sh` | `url_open "$RESOLVED_TARGET"` |
| `command` | `RESOLVED_CMD` (a bash **array**, not a string) is the argv to run; its output is paged | `vcs.sh`, `dir.sh` (no viewer installed) | `preview-pane.sh` pages it directly (`render_command_in_pager`); `open-in-viewer.sh` has no pager, so it re-invokes the same raw token through `open-preview.sh` |
| `viewer` | `RESOLVED_TARGET` is a directory to root the file-viewer at | `dir.sh` (viewer installed) | `open-in-viewer.sh` reuses the file case's goto-path send-keys sequence; `preview-pane.sh` can't drive another pane's socket, so it permanently degrades to paging an `eza --tree`/`ls -la` listing |

`RESOLVED_CMD` is a real array, never a flattened string, because a
command-mode handler runs an external tool (`git show`, `gh pr view`)
against **untrusted clipboard input**. Rebuilding an argv from a joined
string would reopen exactly the shell-injection surface the mode exists to
avoid, see `vcs.sh`'s anchored regexes and its own comment on `git show
--end-of-options` vs `git show --`.

### Adding a new kind

A purely additive kind (mode `file` or `browser` only) needs zero edits to
either pane script:

1. `scripts/handlers/<kind>.sh` with `match_<kind>` / `handle_<kind>`.
2. One line: insert `<kind>` into `HANDLER_KINDS` in `scripts/lib.sh`, before `path`.

A kind that wants to emit `command` or `viewer` for the first time (or that
needs a token-kind-specific interactive fallback, like `bare-name.sh`) is
the one exception where the pane scripts' own `RESOLVED_MODE` case blocks
may need a look, those bodies are the single place all four modes render.

## Virtual link transport

Herdr plugin link handlers receive only resolved http(s) URLs. A plain path
in another terminal pane never reaches a plugin, so the hint overlay does not
try to modify that pane. Instead, the `hint` action scans the origin's
visible text and precomputes an OSC-8 URI per token; `hint-pane` renders
each hinted token wrapped in that URI, so Ctrl+click and the hint letter
share one open path.

Each candidate is rendered with an OSC-8 URI of this shape:

```text
https://herdr-quicklook.invalid/open?token=<percent-encoded-token>
```

`.invalid` is reserved and never intended for network resolution.
`quicklook_link_uri` rejects empty/control-bearing tokens and uses jq's `@uri`
encoder. `quicklook_token_from_link` accepts only the exact prefix, rejects
extra query/fragment fields, decodes it, and requires a byte-for-byte canonical
re-encode before returning the token. The `virtual-token` manifest handler then
runs `open-link`, which clears the clicked sentinel from its environment and
passes the decoded token to `open-preview.sh`.

Repository URLs printed directly by an application do not need the overlay.
The narrower `git-host-token` handler routes only URL shapes quicklook improves
(blob/raw files and pull requests) to the existing `preview` action. Handler
order is significant: the internal sentinel handler stays first.

`hint-pane` must remain an `overlay`, not a popup. Herdr overlays are normal
terminal panes whose OSC-8 cells participate in Ctrl-click resolution; popup
mouse input is forwarded directly to the popup process before link handling.
The shared scanner remains compatible with macOS system Bash 3.2.

## The lesskey three-slot map

The preview overlay is `less`, driven by a `lesskey`-compiled binding file.
`less` exposes exactly **three** independent slots that can shell out to an
external script, and this plugin uses all three:

```
┌─────┬────────────────┬───────────────────────┬──────────────────────────────┐
│ Key │ less action     │ Script                │ How it resumes                │
├─────┼────────────────┼───────────────────────┼──────────────────────────────┤
│ o/v │ visual (1 slot) │ escalate.sh            │ kills the parent less          │
│     │  $VISUAL        │  -> open-in-viewer.sh  │ (hand-off, overlay closes)     │
├─────┼────────────────┼───────────────────────┼──────────────────────────────┤
│ e   │ pshell (`#`)    │ escalate-editor.sh     │ `^P`-suppressed "done" prompt, │
│     │                 │  -> $EDITOR            │ overlay resumes on exit        │
├─────┼────────────────┼───────────────────────┼──────────────────────────────┤
│ d   │ shell (`!`)     │ dirty-diff.sh          │ `^P`-suppressed "done" prompt, │
│     │                 │  -> nested less, git   │ `d`/`q`/Esc-Esc all close the  │
│     │                 │     diff (or delta)    │ nested pager, resuming the file│
└─────┴────────────────┴───────────────────────┴──────────────────────────────┘
```

Three distinct actions, not three bindings of the same one, because `less`
only lets one script own `visual`. `o` claimed it first (escalating to
herdr-file-viewer needs the file+line `%f`/`%lm` expansion that `visual`
gives for free); `e` and `d` each needed their own independent shell-escape,
so they moved to `pshell` and `shell` respectively, the only two other
slots `less` has. **A fourth in-popup key would have nowhere left to bind**
without inventing a dispatcher script that reads a flag file, or similar;
that has not been needed yet.

The two shell-escape slots (`pshell`/`shell`) use **different** `%`-expansion
syntax: `pshell` uses the two-char prompt-style codes (`%g`, `%lm`, …, the
same expansion `visual` gets); `shell` uses a bare, single-char `%` for the
current filename. Mixing them up either glues a stray `g` onto the filename
or splits a spaced filename into two argv elements, both were hit and fixed
empirically while building `d` (a real `less` session, not just a unit
test); see `scripts/dirty-diff.sh`'s header comment for the exact failure
modes.

`\020` (octal for `^P`, CONTROL-P) prefixes both the `pshell` and `shell`
extra strings. Without it, a shell-escape prints `"...done (press
RETURN)"` and waits for a keypress before resuming the pager; `^P`
suppresses that prompt so `e` and `d` resume exactly as seamlessly as `o`'s
hand-off does.

## Panes, actions, and event topology

Action and event commands run headless. Interactive selectors, pagers, and
OSC-8 rendering run in one of four real-TTY overlays:

```
Actions/events (no TTY)                  Overlay panes and state

preview ───────────plugin pane open─────▶ preview pane (preview-pane.sh)
                                                   ▲
recents ───────────plugin pane open─────▶ recents-pick pane
                                             └─ exec, same pane/TTY ───────────┘

hint ──────────────plugin pane open─────▶ hint-pane (in-place hint overlay)
     └ scan in a background subshell          ├─ keypress: exec, same pane/TTY ┘
       (pane read is RPC-safe HERE)           └─ OSC-8 Ctrl+click ─▶ open-link ┘
repository URL Ctrl+click ────────────────────────────────▶ preview
agent status hook ─▶ latest suggestion state ─▶ agent-suggestion ─▶ preview

open-in-viewer ·····herdr socket: send-keys / send-text·····▶ herdr-file-viewer pane (a different plugin)
```

`open-in-viewer`, `recents`, and `hint` cannot do interactive work inside
their action command. They either open a plugin pane or drive an existing
pane through the herdr socket. `recents-pane.sh` and `hint-pane.sh` `exec`
`preview-pane.sh` after selection so resolution, rendering, and recents
recording stay on one path (a directory pick routes into `open-in-viewer.sh`
instead, so it lands in the real file viewer). Two herdr constraints pin
this topology: **never open a plugin pane with `--cwd`** (herdr resolves the
pane's relative manifest command against that cwd, finds nothing, and the
pane flash-closes; every pane receives its cwd as an env var instead), and
**never issue a server RPC from inside a server-spawned overlay pane** (it
deadlocks; the overlay therefore reads two files the action prepared and a
keypress, nothing else).

## Hint picker

`hint` (`scripts/hint.sh` + `scripts/hint-pane.sh`) is the one action that
doesn't start from a single clipboard token - it scans everything currently
rendered on screen and overlays a one-letter hint on each openable token,
in place, pluck-style.

**The acquisition primitive**: `herdr pane read <pane_id> --source visible
--format text` (herdr's own socket API) is the only live dependency in the
whole scan path. `--format text` already strips every ANSI/OSC escape
sequence before the text reaches the plugin (live-verified against a real
running session: a pane printing raw SGR color codes came back
escape-free through `--format text` and with the raw `ESC[...` codes
intact through `--format ansi`, byte-for-byte diffed); `pick_scan_text`
also strips them itself in a defensive pass, so any OTHER caller that
pipes raw/decorated text in stays safe too. See DECISIONS.md for the full
verification method.

**The action/pane split** (`herdr` runs an action's own command with no
TTY, so the interactive keypress lives in a real overlay pane; and the
overlay cannot RPC, so ALL herdr calls live in the action):

1. `hint` (action, no TTY) captures the ORIGIN pane id before it does
   anything else - `herdr pane current` returns the FOCUSED pane, and the
   instant the overlay is focused, that call would return the overlay
   itself. Falls back to `$HERDR_PLUGIN_CONTEXT_JSON`'s `.focused_pane_id`
   (live-verified 2026-07-17; see DECISIONS.md).
2. It reads the pane's visible text ONCE (`pane read`), strips it, and
   writes the snapshot to a temp file. If the clipboard token is visible in
   that snapshot AND resolves, it opens IMMEDIATELY (directory ->
   `open-in-viewer`, everything else -> `preview`), no overlay at all - and
   a stale clipboard can never hijack the key, because the text must be on
   screen. Otherwise it opens `hint-pane` right away and leaves the scan
   running in a BACKGROUND subshell that writes the ranked token list
   (raw, line-no, precomputed OSC-8 URI, label) atomically.
3. `hint-pane` (pane, real TTY, zero RPC) paints the dimmed snapshot
   instantly, polls for the token file (Esc aborts mid-scan), then repaints
   in place with the hint letter overlaid on each token's first character.
   Autowrap is off and the frame is clamped to the pane height, so the
   overlay can never scroll and corrupt its own repaint; a token that
   cannot be re-located on its snapshot line stays pickable from a short
   list under the snapshot. A keypress resolves the chosen token through
   the real handler registry and routes by mode (`viewer` ->
   `open-in-viewer.sh`, else `preview-pane.sh`, exec'd in this same pane).

**The scan/rank/count flow**, entirely inside `pick_scan_text`
(`scripts/lib.sh`), pure text-in/text-out, no live pane or clipboard of its
own:

```
herdr pane read --format text
              │
              ▼
_pick_strip_ansi (defensive; herdr already strips it)
              │
              ▼
tokenize every line into spans, trim wrapping/trailing punctuation   ─┐
              │                                                       │ one awk
              ▼                                                       │ process
dedup: unique span -> bottom-most line-no                            ─┘ (Pass 1)
(each span classified ONCE, not once per occurrence)
              │
              ▼
hoist git state ONCE per scan (rev-parse / worktree list / ls-files)
              │
              ▼
classify each unique span through the SAME HANDLER_KINDS walk        ─┐ bash,
resolve_any_token uses (pure scan-local mirrors, never the            │ zero-fork
live handlers)                                                        ─┘ per span
              │
              ▼
rank: path > url > sha > ref > dir > name                            ─┐ awk + sort
tiebreak: line-no desc, then raw-token asc                            ─┘ (Pass 3)
              │
              ▼
pick_scan_text stdout: <raw>\t<kind>\t<line-no> per candidate
              │
              ▼
pick_count_header: N on screen . A path . B url . ...
```

Why scan-local mirrors and not the real handlers: the real handlers
(`handle_path`, `handle_dir`, `handle_github`) have side effects (global
mutation, live `git`/herdr calls per invocation) appropriate for OPENING
one token, but wrong for classifying every span on a busy screen - see the
CRITICAL performance fix in DECISIONS.md (an unmirrored first pass measured
143s on a 500-line screen; the mirrored, hoisted rewrite brought that to
~1s). `pick_scan_text` never calls the OPEN-time handlers at all;
`hint-pane.sh`'s keypress still hands the chosen raw token to the real
handler registry exactly like every other open.

**Fast mode** (`QUICKLOOK_SCAN_FAST=1`, the hint action's default): the
classification step goes shape-first - slash/tilde/dotted-extension shapes
classify with zero filesystem work, a single-slash extensionless token
(`pair/leaf` vs prose `rust/go`) must pass one `-e` stat, the bare-name
fuzzy is skipped entirely, and a github URL stays `url` (the open step
finds the checkout). Resolution correctness is unaffected: the open step
always re-resolves through the full registry. `QUICKLOOK_HINT_VERIFIED=1`
restores the fully-verified scan; `QUICKLOOK_HINT_NAMES=1` re-enables the
bare-name fuzzy.

**Runs on any bash, including macOS's system `/bin/bash` (3.2).** The
tokenize/trim/dedup pass and the final tier-rank/sort are a single awk
process each rather than a bash loop; the one remaining per-span bash step
(classification, which needs the filesystem-aware scan-local mirrors above)
writes its result to a fixed-name global instead of a `local -n` outvar, so
there is no subprocess per span on any bash version. This superseded an
earlier `local -A`/`local -n`-based implementation that needed bash >= 4.3
and a runtime version guard; see DECISIONS.md (ops-toolkit) for the
rewrite and the measured before/after on both a modern bash and bash 3.2.

## Recents state

Every successful open, `file`, `browser`, or `command`/`viewer`, is
recorded to a small, bounded, deduped log:

```
${XDG_STATE_HOME:-~/.local/state}/herdr-quicklook/recents
```

One raw token per line, **most-recent-last** on disk (`recents_list` reverses
it for readers). Writes are atomic: a temp file in the same directory, then
`mv -f` over the real file, so a concurrent reader never sees a
half-written log.

Two guards make this safe to run unattended:

- **`recents_path_is_safe`**: walks every ancestor directory of the state
  file looking for a `.git` entry (a directory for a normal repo, a file
  for a worktree/submodule gitlink). If any ancestor is a git working tree,
  `record_open` refuses to write. This is the hard rule: recents state must
  never land inside a repo, however `XDG_STATE_HOME`/`$HOME` ends up
  configured on a given machine.
- **Best-effort, always**: an unwritable state dir, a failed guard check, or
  any write failure is silently swallowed. Recording a "recent" must never
  block the open it is recording.

## Agent suggestion state

The manifest subscribes only to `pane.agent_status_changed`; herdr deliberately
does not expose high-volume output changes as plugin hooks. The command exits
before reading a pane unless `QUICKLOOK_AGENT_SUGGESTIONS` is `notify` or
`preview`, so the default installation has no background scanner. Enabled hooks
reuse the same Bash 3.2-compatible pane scanner as the hint picker.

For an enabled pane, `working` creates one baseline under
`$HERDR_PLUGIN_STATE_DIR/agent-suggestions`. Further `working` presentation
events leave it untouched. `blocked` keeps the same baseline. The first
`done`/`idle` event reads `recent-unwrapped`, computes the suffix after the
first changed line, removes the baseline, and scans only that delta. This
avoids repeatedly suggesting tokens from older turns and naturally dedupes a
subsequent `done` to `idle` presentation change.

A per-pane PID-symlink lock serializes asynchronous event commands and
recovers after an interrupted hook. The selected candidate and producing cwd
are atomically written as `latest.json`; the
`agent-suggestion` action uses that cwd when opening `preview`. A missing
baseline intentionally yields no suggestion rather than scanning stale
scrollback after installation or restart.

## Security notes (cross-cutting, not one handler's job)

- **`command`-mode argv safety**: `RESOLVED_CMD` is always a bash array built
  by quoting the raw token as one element (`git show --end-of-options
  "$sha"`, `gh pr view "$n"`), never a string later re-split. `vcs.sh`'s
  regexes are anchored (`^...$`) so an accepted token can never itself look
  like a flag, and the argv-array contract holds independent of that regex
  (see `tests/handlers-vcs.bats`' "argv shape control" case, which calls
  `handle_vcs` directly, bypassing `match_vcs`, to prove the quoting itself
  is what keeps a space-containing value one argv element).
- **`--end-of-options`, not `--`**: `git show --end-of-options "$sha"`
  rejects a hex-shaped-but-fake SHA loudly. `git show -- "$sha"` would
  instead silently reinterpret the bad SHA as a pathspec on `HEAD` and print
  a real-looking (wrong) commit, worse than an error, because it looks
  like data.
- **Path-traversal guard** (`unsafe_relpath`): a GitHub/GitLab/Bitbucket URL
  path is always repo-relative; an absolute or `..`-traversal candidate is a
  smuggled path and is refused before it ever reaches a `-f` test.
- **Control-character guard**: `open-in-viewer.sh` refuses a resolved
  filename containing a control byte (e.g. an embedded newline) before
  typing it into the file-viewer TUI over the herdr socket, a control byte
  there would inject extra keystrokes into that plugin.

## Testing

`bats tests/` sources `scripts/lib.sh` directly for unit-level coverage
(the resolve chain, token parsing, priority, and virtual-link canonicalization)
and runs the actual scripts under `run` with stubbed tools for script-level
coverage. That includes dispatch wiring, pane-script `RESOLVED_MODE` cases,
OSC-8 overlay output, per-turn agent baseline/delta behavior, and real
`lesskey`/`less` sessions for the in-popup keys. `shellcheck -x scripts/*.sh
scripts/handlers/*.sh` is the companion static check. Both run in
`./scripts/release.sh` before it mutates anything.
