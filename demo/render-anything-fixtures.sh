#!/bin/bash
# Generates the three neutral /private/tmp scratch dirs the v0.4 render-tour
# tapes (render-images-tour.tape, render-docs-tour.tape,
# render-data-fallback.tape) record against, plus a tiny `open` wrapper in
# each one. Never /tmp - macOS's /tmp is a symlink to /private/tmp and a
# shell whose $PWD shows the symlinked form breaks repo-containment checks
# elsewhere in this plugin (see demo/README.md's landmines). Every fixture
# is invented placeholder content (fruit names, hello-world shapes) - never
# real data.
#
# Usage: ./demo/render-anything-fixtures.sh   (run from this checkout)
set -euo pipefail

worktree="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

write_open_wrapper() {
  # A short relative-name wrapper around the REAL production entrypoint
  # (scripts/open-preview.sh - the same script the prefix+v keybinding
  # itself runs), so a tape can type "./open sample.png" instead of a long
  # absolute path four times over, keeping each tour under its 30s budget.
  #
  # Two things this wrapper does that a bare `bash open-preview.sh <name>`
  # typed at the prompt cannot: (1) it resolves <name> against ITS OWN
  # directory ("$dir/$1", always absolute) before handing it to
  # open-preview.sh - open-preview.sh derives the overlay pane's cwd from
  # $HERDR_PLUGIN_CONTEXT_JSON, which is only populated when herdr itself
  # dispatches an action (a real keybinding, or `herdr plugin action
  # invoke`), never when the script is just run as a plain shell command,
  # so a bare relative filename would resolve against the overlay's own
  # default cwd instead of this scratch dir and fail to open; (2) it
  # redirects `herdr plugin pane open`'s own JSON acknowledgment (printed
  # to THIS pane, not the new overlay pane) to /dev/null - undirected, that
  # ack text pollutes the recording same as the existing tapes' own
  # `>/dev/null 2>&1` on `herdr plugin action invoke preview` calls.
  # shellcheck disable=SC2016  # the $dir/$1 refs are literal, meant for the GENERATED wrapper, not this shell
  printf '#!/bin/bash\ndir="%s"\nexec bash "%s/scripts/open-preview.sh" "$dir/$1" >/dev/null 2>&1\n' "$1" "$worktree" >"$1/open"
  chmod +x "$1/open"
}

# --- images tour: png, gif, svg, pdf ---
img_dir=/private/tmp/ql-demo-images
mkdir -p "$img_dir"
sips -s format png "$worktree/demo/linkify.gif" --out "$img_dir/sample.png" >/dev/null
# A SINGLE-FRAME gif, not a real animation and not a repo demo recording.
# Two independent landmines rule out anything with more than one frame, live
# with the chafa 1.18.2 on this machine: (1) gif.sh's shipped invocation is
# `chafa --animate -d N -- <path>` - chafa 1.18.2 requires `--animate=BOOL`
# (space-separated `--animate -d` mis-parses "-d" AS --animate's value:
# "chafa: Animate mode must be one of [on, off]"), so that call always
# errors and falls through to gif.sh's own fallback, `chafa --format symbols
# -- <path>` with NO --animate/-d at all; (2) chafa defaults --animate to ON
# and an unset --duration to INFINITE for an animation, so on a real
# multi-frame gif that fallback call itself free-runs forever in a real TTY
# (confirmed live via the herdr socket API: pane stayed open unbounded,
# `ps` showed no dead process, only cursor-blink-level diffs between
# polls). A single-frame file sidesteps both: chafa has nothing to loop and
# the render (still image.sh path, reused via render_gif's fallback) exits
# straight to the "press any key to close" prompt like every other still
# render. This is a real, worth-flagging renderer-side finding for a future
# goal (out of scope here - demo/docs only); see the tape's own header
# comment and the sub-goal's PR deviations.
ffmpeg -y -f lavfi -i "mandelbrot=size=200x150:rate=1" -frames:v 1 "$img_dir/sample.gif" >/dev/null 2>&1
cat >"$img_dir/sample.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
  <rect x="10" y="10" width="80" height="80" fill="#61afef"/>
  <circle cx="150" cy="50" r="40" fill="#e06c75"/>
  <polygon points="40,150 90,190 10,190" fill="#98c379"/>
</svg>
EOF
sips -s format pdf "$img_dir/sample.png" --out "$img_dir/sample.pdf" >/dev/null
write_open_wrapper "$img_dir"

# --- docs tour: md, docx, ipynb ---
docs_dir=/private/tmp/ql-demo-docs
mkdir -p "$docs_dir"
cat >"$docs_dir/sample.md" <<'EOF'
# Fruit Stand Notes

A short readme for the fruit stand inventory tool.

## Features

- Track apples, bananas, and mangoes
- Daily price sheet export
- Low-stock alerts

## Quick start

```sh
fruit-stand init
fruit-stand add apple --qty 40
```

See `CONTRIBUTING.md` for how to add a new fruit type.
EOF
pandoc "$docs_dir/sample.md" -o "$docs_dir/sample.docx"
cat >"$docs_dir/sample.ipynb" <<'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": ["# Fruit Counter\n", "A tiny notebook that counts fruit."]
  },
  {
   "cell_type": "code",
   "execution_count": 1,
   "metadata": {},
   "outputs": [],
   "source": ["fruits = ['apple', 'banana', 'mango']\n", "print(len(fruits))"]
  }
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
  "language_info": {"name": "python", "version": "3.11"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF
write_open_wrapper "$docs_dir"

# --- data + fallback tour: csv, json, sqlite, an unknown/corrupt binary ---
data_dir=/private/tmp/ql-demo-data
mkdir -p "$data_dir"
cat >"$data_dir/sample.csv" <<'EOF'
fruit,qty,price_usd
apple,120,0.50
banana,80,0.25
mango,35,1.20
kiwi,60,0.75
EOF
printf '%s' '{"fruit_stand":{"name":"Sunny Fruit Co","location":"riverside","items":[{"name":"apple","qty":120},{"name":"banana","qty":80}],"open":true}}' >"$data_dir/sample.json"
rm -f "$data_dir/sample.db"
sqlite3 "$data_dir/sample.db" <<'EOF'
create table users(id integer primary key, name text, favorite_fruit text);
insert into users(name, favorite_fruit) values ('Alice','mango'),('Bob','kiwi'),('Cy','banana');
create table orders(id integer primary key, user_id integer, fruit text, qty integer);
insert into orders(user_id, fruit, qty) values (1,'mango',3),(2,'kiwi',5);
EOF
# mystery.ipynb: the first 800 bytes of /bin/ls, real binary data wearing a
# familiar extension - the negative control. ipynb.sh's own binary-encoding
# guard declines it, text.sh declines it for the same reason, and it falls
# all the way to the always-on fallback guard (file(1) + hexyl + an install
# hint), proving a corrupt/misleading file can never reach a formatter.
head -c 800 /bin/ls >"$data_dir/mystery.ipynb"
write_open_wrapper "$data_dir"

echo "fixtures ready: $img_dir, $docs_dir, $data_dir"
