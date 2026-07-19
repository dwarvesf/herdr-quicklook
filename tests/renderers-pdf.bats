#!/usr/bin/env bats
# Tests for scripts/renderers/pdf.sh (pdf via pdftoppm+chafa poster and
# pdftotext text mode, v0.4 SG-06/P2). Same fixture/sourcing shape as
# tests/render-registry.bats.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # A minimal, REAL pdf (verified via `file --mime-type` = application/pdf).
  {
    printf '%%PDF-1.4\n'
    printf '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
    printf '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
    printf '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]>>endobj\n'
    printf 'trailer<</Size 4/Root 1 0 R>>\n%%%%EOF\n'
  } >"$FIX/t.pdf"
  # A real pdf whose stream carries actual binary bytes (a NUL byte) -
  # representative of a genuine PDF (compressed/binary stream content),
  # unlike the plain-ASCII fixture above. file(1) still reports
  # application/pdf but mime-ENCODING is "binary" - this is the fixture the
  # "poppler entirely absent" degrade test needs, since an all-ASCII pdf
  # would (like an svg) instead fall through to the text renderer.
  {
    printf '%%PDF-1.4\n'
    printf '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
    printf '4 0 obj<</Length 8>>\nstream\n'
    printf '\x00\x01\x02\x03\x04\x05\x06\x07'
    printf '\nendstream\nendobj\n'
    printf 'trailer<</Size 5/Root 1 0 R>>\n%%%%EOF\n'
  } >"$FIX/bin.pdf"
  # binary garbage wearing a .pdf extension - the negative control.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' >"$FIX/fake.pdf"

  STUB="$(mktemp -d)"
  export PDFTOPPM_ARGV_FILE="$FIX/pdftoppm.argv"
  export PDFTOTEXT_ARGV_FILE="$FIX/pdftotext.argv"
  export CHAFA_ARGV_FILE="$FIX/chafa.argv"
}

teardown() {
  cd /
  rm -rf "$FIX" "$STUB"
}

_stub_pdftoppm_ok() {
  cat > "$STUB/pdftoppm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$PDFTOPPM_ARGV_FILE"
last="${@: -1}"
: > "${last}.png"
exit 0
SH
  chmod +x "$STUB/pdftoppm"
}

_stub_pdftotext_ok() {
  cat > "$STUB/pdftotext" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$PDFTOTEXT_ARGV_FILE"
printf 'PDFTOTEXT_OUTPUT\n'
exit 0
SH
  chmod +x "$STUB/pdftotext"
}

_stub_chafa() {
  cat > "$STUB/chafa" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CHAFA_ARGV_FILE"
exit 0
SH
  chmod +x "$STUB/chafa"
}

# ---- match: both modes present ----

@test "match_render_pdf: matches a real .pdf when pdftoppm+chafa AND pdftotext are all present" {
  _stub_pdftoppm_ok
  _stub_pdftotext_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  match_render_pdf "$FIX/t.pdf"
}

@test "match_render_pdf: matches poster-only (pdftotext absent, pdftoppm+chafa present)" {
  _stub_pdftoppm_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  match_render_pdf "$FIX/t.pdf"
}

@test "match_render_pdf: matches text-only (pdftoppm absent, pdftotext present)" {
  _stub_pdftotext_ok
  export PATH="$STUB:/usr/bin:/bin"
  match_render_pdf "$FIX/t.pdf"
}

@test "match_render_pdf: declines a non-pdf extension" {
  _stub_pdftoppm_ok
  _stub_pdftotext_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  printf 'hello\n' > "$FIX/t.md"
  ! match_render_pdf "$FIX/t.md"
}

# ---- degrade: poppler entirely absent ----

@test "match_render_pdf: declines when all of pdftoppm/pdftotext are absent (PATH excludes /opt/homebrew/bin and /usr/local/bin)" {
  export PATH="/usr/bin:/bin"
  ! match_render_pdf "$FIX/t.pdf"
}

@test "render-registry: poppler absent - a real (binary-stream) pdf routes to fallback via render_any, never text" {
  export PATH="/usr/bin:/bin"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_text() { printf 'TEXT:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/bin.pdf'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/bin.pdf" ]
}

# ---- negative control: type mismatch, not just extension ----

@test "match_render_pdf: declines binary garbage renamed .pdf (keys on type, not extension)" {
  _stub_pdftoppm_ok
  _stub_pdftotext_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  ! match_render_pdf "$FIX/fake.pdf"
}

@test "render-registry: binary garbage renamed .pdf routes to fallback, never pdftoppm/pdftotext" {
  _stub_pdftoppm_ok
  _stub_pdftotext_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.pdf'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.pdf" ]
  [ ! -e "$PDFTOPPM_ARGV_FILE" ]
  [ ! -e "$PDFTOTEXT_ARGV_FILE" ]
}

# ---- render: poster + text together ----

@test "render_pdf: full mode draws the page-1 poster via render_image (chafa) then pages pdftotext's output" {
  _stub_pdftoppm_ok
  _stub_pdftotext_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_pdf '$FIX/t.pdf' <<<'x'"
  [ "$status" -eq 0 ]
  [ -f "$PDFTOPPM_ARGV_FILE" ]
  grep -qx -- '-singlefile' "$PDFTOPPM_ARGV_FILE"
  grep -qx -- "$FIX/t.pdf" "$PDFTOPPM_ARGV_FILE"
  tmp_prefix="$(tail -1 "$PDFTOPPM_ARGV_FILE")"
  [ -f "$CHAFA_ARGV_FILE" ]
  grep -qx -- "${tmp_prefix}.png" "$CHAFA_ARGV_FILE"
  # the poster temp png is cleaned up after the render.
  [ ! -e "${tmp_prefix}.png" ]
  [ -f "$PDFTOTEXT_ARGV_FILE" ]
  grep -qx -- "$FIX/t.pdf" "$PDFTOTEXT_ARGV_FILE"
  [[ "$output" == *"PDFTOTEXT_OUTPUT"* ]]
}

# ---- render: poster-only (pdftotext absent) ----

@test "render_pdf: poster-only mode draws via chafa and never calls pdftotext" {
  _stub_pdftoppm_ok
  _stub_chafa
  export PATH="$STUB:$PATH"
  run bash -c ". '$LIB'; render_pdf '$FIX/t.pdf' <<<'x'"
  [ "$status" -eq 0 ]
  [ -f "$CHAFA_ARGV_FILE" ]
  [ ! -e "$PDFTOTEXT_ARGV_FILE" ]
}

# ---- render: text-only (poster tools absent) ----

@test "render_pdf: text-only mode pages pdftotext's output and never calls pdftoppm/chafa" {
  _stub_pdftotext_ok
  export PATH="$STUB:/usr/bin:/bin"
  run bash -c ". '$LIB'; render_pdf '$FIX/t.pdf'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PDFTOTEXT_OUTPUT"* ]]
  [ ! -e "$PDFTOPPM_ARGV_FILE" ]
  [ ! -e "$CHAFA_ARGV_FILE" ]
}
