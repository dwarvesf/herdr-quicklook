#!/usr/bin/env bash
# install-renderers.sh: brew-first installer for herdr-quicklook's v0.4
# render-anything optional tools, grouped into P1/P2/P3 tiers so a user only
# installs the tools they actually want. `--dry-run` (the default, a bare
# invocation included) never touches the host: it previews the brew formula
# per tier, skipping anything already on PATH, and exits 0. `--apply` is the
# explicit opt-in that actually runs `brew install`. Never `curl | bash`;
# when brew itself is absent this prints the manual (apt/pip/cargo) fallback
# line as a comment and moves on -- it never executes a fallback command,
# and never fails hard just because brew (or a formula) is missing.
#
# Tool -> formula map (ROADMAP.md's Type->tool->render table, this
# sub-goal's design): p1 = glow, chafa, hexyl (Wave 2: markdown, images +
# animated gif, the always-on file(1)+hexyl fallback). p2 = librsvg
# (rsvg-convert), poppler (pdftoppm + pdftotext), qsv, jq (Wave 3's P2 pack:
# svg/pdf/csv/json -- the archive type's unzip/tar are base-system, never
# installed here). p3 = pandoc, ffmpeg (ffprobe + ffmpeg), sqlite (sqlite3)
# (Wave 3's P3 pack: ipynb/office/media/sqlite+plist). unzip/tar/plutil/file
# are base-system on macOS + Linux and never appear in the table below.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
usage: install-renderers.sh [--dry-run|--apply] [--p1] [--p2] [--p3]

  --dry-run   preview only, touches nothing (DEFAULT; same as a bare invocation)
  --apply     actually run `brew install` for anything missing
  --p1        select the P1 tier (glow, chafa, hexyl)
  --p2        select the P2 tier (librsvg, poppler, qsv, jq)
  --p3        select the P3 tier (pandoc, ffmpeg, sqlite)
              repeatable; default (no tier flag given) covers all three tiers
  -h, --help  show this message
EOF
}

die() {
  printf 'install-renderers: %s\n' "$1" >&2
  usage >&2
  exit 1
}

# tier:formula:check-bins(comma-separated):manual fallback (documented only,
# never executed). One line per tool; keep in the fixed p1/p2/p3 tier order
# above so the preview output reads top-down by priority.
tool_table() {
  cat <<'EOF'
p1:glow:glow:apt install glow (or see https://github.com/charmbracelet/glow#installation)
p1:chafa:chafa:apt install chafa
p1:hexyl:hexyl:apt install hexyl (or: cargo install hexyl)
p2:librsvg:rsvg-convert:apt install librsvg2-bin
p2:poppler:pdftoppm,pdftotext:apt install poppler-utils
p2:qsv:qsv:cargo install qsv (no apt package)
p2:jq:jq:apt install jq
p3:pandoc:pandoc:apt install pandoc
p3:ffmpeg:ffprobe,ffmpeg:apt install ffmpeg
p3:sqlite:sqlite3:apt install sqlite3
EOF
}

apply=0
# tiers_selected: a space-separated word list, not a bash array. macOS
# ships bash 3.2 as /bin/bash (what `#!/usr/bin/env bash` resolves to on a
# host with no Homebrew bash yet -- exactly the host this script exists to
# bootstrap), and 3.2 raises "unbound variable" under `set -u` when
# expanding "${arr[@]}" on a still-empty array. A plain word-split string
# sidesteps that entirely; tier names are simple tokens, never quoted or
# space-containing, so word-splitting them back apart is safe.
tiers_selected=""

tier_selected() {
  case " $tiers_selected " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) apply=0 ;;
    --apply) apply=1 ;;
    --p1) tier_selected p1 || tiers_selected="$tiers_selected p1" ;;
    --p2) tier_selected p2 || tiers_selected="$tiers_selected p2" ;;
    --p3) tier_selected p3 || tiers_selected="$tiers_selected p3" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown flag: $1" ;;
  esac
  shift
done

[ -z "$tiers_selected" ] && tiers_selected="p1 p2 p3"

brew_bin="$(command -v brew || true)"

if [ "$apply" -eq 1 ]; then
  echo "install-renderers: --apply (brew: ${brew_bin:-not found})"
else
  echo "install-renderers: --dry-run, previewing only -- nothing will be installed"
fi

while IFS=: read -r tier formula bins manual; do
  [ -z "$tier" ] && continue
  tier_selected "$tier" || continue

  have=1
  IFS=',' read -ra bin_list <<<"$bins"
  for b in "${bin_list[@]}"; do
    command -v "$b" >/dev/null 2>&1 || have=0
  done
  bins_display="${bins//,/ + }"

  if [ "$have" -eq 1 ]; then
    echo "  [$tier] already installed: $formula ($bins_display)"
    continue
  fi

  if [ "$apply" -eq 0 ]; then
    if [ -n "$brew_bin" ]; then
      echo "  [$tier] would install: brew install $formula   (provides: $bins_display)"
    else
      echo "  [$tier] # no brew found -- install manually: $manual"
    fi
    continue
  fi

  # --apply from here down.
  if [ -n "$brew_bin" ]; then
    echo "  [$tier] installing: brew install $formula"
    "$brew_bin" install "$formula" ||
      echo "  [$tier] brew install $formula failed, skipping (not fatal)" >&2
  else
    echo "  [$tier] # no brew found -- install manually: $manual"
  fi
done < <(tool_table)

echo "install-renderers: unzip, tar, plutil, file are base-system -- already present, never installed by this script"
