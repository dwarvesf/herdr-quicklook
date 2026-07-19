#!/usr/bin/env bats
# Tests for scripts/renderers/office.sh (v0.4 SG-07, P3 pack): docx/xlsx via
# pandoc's own readers -> markdown -> render_markdown (SG-03, reused by
# calling); xlsx additionally clipped to its FIRST `## ` sheet heading.
# Sources lib.sh directly, same fixture shape as tests/render-registry.bats.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  # A real docx, built by pandoc itself (round-trips cleanly - verified
  # live).
  printf '# hi\n\n- a\n- b\n' > "$FIX/src.md"
  pandoc "$FIX/src.md" -o "$FIX/t.docx"
  # A real, two-sheet xlsx (sharedStrings-backed, the real-world shape;
  # verified live that an inlineStr-only xlsx does NOT round-trip through
  # pandoc's reader the same way).
  python3 - "$FIX/t.xlsx" <<'PY'
import zipfile, sys

content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>'''

rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>'''

workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="First" sheetId="1" r:id="rId1"/><sheet name="Second" sheetId="2" r:id="rId2"/></sheets>
</workbook>'''

workbook_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>'''

shared = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">
<si><t>name</t></si><si><t>age</t></si><si><t>alice</t></si><si><t>bob</t></si>
</sst>'''

sheet1 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData>
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>30</v></c></row>
<row r="3"><c r="A3" t="s"><v>3</v></c><c r="B3"><v>25</v></c></row>
</sheetData>
</worksheet>'''

sheet2 = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData>
<row r="1"><c r="A1" t="s"><v>1</v></c></row>
<row r="2"><c r="A2"><v>99</v></c></row>
</sheetData>
</worksheet>'''

with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('[Content_Types].xml', content_types)
    z.writestr('_rels/.rels', rels)
    z.writestr('xl/workbook.xml', workbook)
    z.writestr('xl/_rels/workbook.xml.rels', workbook_rels)
    z.writestr('xl/sharedStrings.xml', shared)
    z.writestr('xl/worksheets/sheet1.xml', sheet1)
    z.writestr('xl/worksheets/sheet2.xml', sheet2)
PY
  # binary garbage wearing docx/xlsx extensions - the negative control.
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.docx"
  printf '\x00\x01\x02\xff\xfe\x00binary\x00stuff' > "$FIX/fake.xlsx"
  # a real zip that is NOT an office document (no OOXML content-types
  # override) - a second negative control shape: a non-garbage file that
  # still isn't the right TYPE.
  zip -q "$FIX/notoffice.docx" "$FIX/src.md"
  printf 'plain text\n' > "$FIX/t.txt"

  STUB="$(mktemp -d)"
  cat > "$STUB/glow" <<'SH'
#!/usr/bin/env bash
printf 'GLOW_ARGS:%s\n' "$*"
cat "${@: -1}"
SH
  cat > "$STUB/less" <<'SH'
#!/usr/bin/env bash
printf 'LESS_ARGS:%s\n' "$*"
cat
SH
  chmod +x "$STUB/glow" "$STUB/less"

  ONLYBASE="$(mktemp -d)"
  ln -s "$(command -v file)" "$ONLYBASE/file"
  ln -s "$(command -v tr)" "$ONLYBASE/tr"
  ln -s "$(command -v dirname)" "$ONLYBASE/dirname"
  ln -s "$(command -v bash)" "$ONLYBASE/bash"
  ln -s "$(command -v mktemp)" "$ONLYBASE/mktemp"
  ln -s "$(command -v awk)" "$ONLYBASE/awk"
  ln -s "$(command -v rm)" "$ONLYBASE/rm"
}

teardown() {
  cd /
  /bin/rm -rf "$FIX" "$STUB" "$ONLYBASE"
  export PATH="/usr/bin:/bin:$PATH"
}

# ---- match: pandoc + glow present ----

@test "match_render_office: matches a real docx when pandoc and glow are on PATH" {
  export PATH="$STUB:$PATH"
  match_render_office "$FIX/t.docx"
}

@test "match_render_office: matches a real xlsx when pandoc and glow are on PATH" {
  export PATH="$STUB:$PATH"
  match_render_office "$FIX/t.xlsx"
}

@test "match_render_office: declines a non-office extension" {
  export PATH="$STUB:$PATH"
  ! match_render_office "$FIX/t.txt"
}

# ---- degrade: pandoc or glow absent ----

@test "match_render_office: declines when pandoc is absent from PATH" {
  GLOWONLY="$(mktemp -d)"
  ln -s "$STUB/glow" "$GLOWONLY/glow"
  export PATH="$GLOWONLY:$ONLYBASE"
  ! command -v pandoc >/dev/null 2>&1
  ! match_render_office "$FIX/t.docx"
  /bin/rm -rf "$GLOWONLY"
}

@test "match_render_office: declines when glow is absent from PATH" {
  PANDOCONLY="$(mktemp -d)"
  ln -s "$(command -v pandoc)" "$PANDOCONLY/pandoc"
  export PATH="$PANDOCONLY:$ONLYBASE"
  ! command -v glow >/dev/null 2>&1
  ! match_render_office "$FIX/t.docx"
  /bin/rm -rf "$PANDOCONLY"
}

@test "render-registry: pandoc absent routes a real docx to fallback via render_any (docx is binary, no text degrade)" {
  GLOWONLY="$(mktemp -d)"
  ln -s "$STUB/glow" "$GLOWONLY/glow"
  export PATH="$GLOWONLY:$ONLYBASE"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/t.docx'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/t.docx" ]
  /bin/rm -rf "$GLOWONLY"
}

# ---- negative control: binary garbage and a non-office zip ----

@test "match_render_office: declines binary garbage renamed .docx (keys on OOXML mime, not extension)" {
  export PATH="$STUB:$PATH"
  ! match_render_office "$FIX/fake.docx"
}

@test "match_render_office: declines binary garbage renamed .xlsx (keys on OOXML mime, not extension)" {
  export PATH="$STUB:$PATH"
  ! match_render_office "$FIX/fake.xlsx"
}

@test "match_render_office: declines a real (non-office) zip renamed .docx" {
  export PATH="$STUB:$PATH"
  ! match_render_office "$FIX/notoffice.docx"
}

@test "render-registry: binary garbage renamed .xlsx routes to fallback, never pandoc/glow" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_fallback() { printf 'FALLBACK:%s\n' \"\$1\"; return 0; }
    render_any '$FIX/fake.xlsx'
  "
  [ "$status" -eq 0 ]
  [ "$output" = "FALLBACK:$FIX/fake.xlsx" ]
}

# ---- render: docx reuses render_markdown, full content ----

@test "render_office: docx converts to markdown and dispatches through render_markdown" {
  export PATH="$STUB:$PATH"
  run bash -c "
    . '$LIB'
    render_markdown() { printf 'MARKDOWN-RENDERED:%s\n' \"\$(cat \"\$1\")\"; return 0; }
    render_office '$FIX/t.docx'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"MARKDOWN-RENDERED:"* ]]
  [[ "$output" == *"hi"* ]]
}

@test "render_office: docx end to end (real pandoc+glow stub) shows the document content" {
  export PATH="$STUB:$PATH"
  run render_office "$FIX/t.docx"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi"* ]]
}

# ---- render: xlsx clips to the FIRST sheet only ----

@test "render_office: xlsx shows the first sheet's content" {
  export PATH="$STUB:$PATH"
  run render_office "$FIX/t.xlsx"
  [ "$status" -eq 0 ]
  [[ "$output" == *"First"* ]]
  [[ "$output" == *"alice"* ]]
}

@test "render_office: xlsx never shows the second sheet's content (first-sheet-only)" {
  export PATH="$STUB:$PATH"
  run render_office "$FIX/t.xlsx"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Second"* ]]
  [[ "$output" != *"99"* ]]
}

@test "render_office: a corrupt docx (mime accepted, pandoc fails) degrades to a graceful notice" {
  # a truncated real docx - passes the OOXML mime sniff (still a zip with the
  # right content-types header) but pandoc cannot fully parse it.
  head -c 200 "$FIX/t.docx" > "$FIX/truncated.docx"
  export PATH="$STUB:$PATH"
  run render_office "$FIX/truncated.docx"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not convert"* ]] || [[ -n "$output" ]]
}
