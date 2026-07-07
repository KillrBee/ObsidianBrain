#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() {
  test_env_setup
  have_markitdown || skip "markitdown not available (run make install-dev)"
  install_default
  [ "$status" -eq 0 ]
}
teardown() { test_env_teardown; }

drop() { cp "$REPO_ROOT/tests/fixtures/$1" "$VAULT/00-inbox/raw-drops/"; }

@test "pdf, docx, pptx, xlsx and html convert with valid frontmatter (spec §24.3-5)" {
  drop sample.pdf; drop sample.docx; drop sample.pptx; drop sample.xlsx; drop sample.html
  run "$VAULT/70-scripts/convert/convert_new_documents.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"converted=5"* ]]

  [ -f "$VAULT/20-converted/pdf-md/sample.md" ]
  [ -f "$VAULT/20-converted/docx-md/sample.md" ]
  [ -f "$VAULT/20-converted/pptx-md/sample.md" ]
  [ -f "$VAULT/20-converted/xlsx-md/sample.md" ]
  [ -f "$VAULT/20-converted/html-md/sample.md" ]

  # Inbox drained; originals routed by type.
  [ -z "$(find "$VAULT/00-inbox/raw-drops" -type f ! -name '.gitkeep')" ]
  [ -f "$VAULT/10-originals/pdf/sample.pdf" ]
  [ -f "$VAULT/10-originals/docx/sample.docx" ]

  # Frontmatter passes the source_conversion schema.
  run "$SB_PYTHON" "$VAULT/70-scripts/maintenance/validate_frontmatter.py" --vault "$VAULT" --path 20-converted
  [ "$status" -eq 0 ]

  # Converted note points back at its original with a checksum.
  "$SB_PYTHON" - "$VAULT" <<'EOF'
import sys
from pathlib import Path
vault = Path(sys.argv[1])
sys.path.insert(0, str(vault / "70-scripts" / "lib"))
import sb_frontmatter
meta, body = sb_frontmatter.read_note(vault / "20-converted/docx-md/sample.md")
assert meta["source_file"] == "10-originals/docx/sample.docx", meta["source_file"]
assert meta["source_checksum"].startswith("sha256:")
assert meta["trust_level"] == "source-derived"
assert meta["review_status"] == "unreviewed"
assert "Identity resolution" in body
EOF
}

@test "originals are byte-identical after conversion (spec §24.12)" {
  drop sample.docx
  before="$(shasum -a 256 "$REPO_ROOT/tests/fixtures/sample.docx" | awk '{print $1}')"
  run "$VAULT/70-scripts/convert/convert_new_documents.sh"
  [ "$status" -eq 0 ]
  after="$(shasum -a 256 "$VAULT/10-originals/docx/sample.docx" | awk '{print $1}')"
  [ "$before" = "$after" ]
}

@test "corrupt input records a manifest failure and does not abort the batch" {
  drop corrupt.pdf; drop sample.html
  run "$VAULT/70-scripts/convert/convert_new_documents.sh"
  [ "$status" -ne 0 ]                     # pipeline reports the failure
  [[ "$output" == *"failed=1"* ]]
  [[ "$output" == *"converted=1"* ]]      # the good file still converted
  manifest="$VAULT/60-index-config/manifests/conversion-manifest.json"
  [ "$(json_get "$manifest" 'any(e["conversion_status"] == "failure" for e in d["documents"])')" = "True" ]
  [ -s "$VAULT/80-logs/conversion/conversion.jsonl" ]
}

@test "reconversion is checksum-deduped; --force reconverts" {
  drop sample.html
  run "$VAULT/70-scripts/convert/convert_new_documents.sh"
  [ "$status" -eq 0 ]
  run "$VAULT/70-scripts/convert/convert_new_documents.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"converted=0"* ]]
  [[ "$output" == *"skipped="* ]]
  manifest="$VAULT/60-index-config/manifests/conversion-manifest.json"
  # Exactly one manifest entry for this file (the installer's welcome-sample
  # is a separate document).
  [ "$(json_get "$manifest" 'sum(1 for e in d["documents"] if e["source_path"] == "10-originals/html/sample.html")')" = "1" ]

  run "$VAULT/70-scripts/convert/reconvert_document.sh" "$VAULT/10-originals/html/sample.html"
  [ "$status" -eq 0 ]
  [ "$(json_get "$manifest" 'sum(1 for e in d["documents"] if e["source_path"] == "10-originals/html/sample.html")')" = "1" ]
}

@test "converted sources are searchable via search_sources (spec §24.6)" {
  drop sample.docx
  run "$VAULT/70-scripts/convert/convert_new_documents.sh"
  [ "$status" -eq 0 ]
  run "$VAULT/70-scripts/search/search_sources.sh" --query "identity resolution survivorship"
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert any("docx-md/sample.md" in r["path"] for r in d["results"]), d["results"]
r = [x for x in d["results"] if "docx-md/sample.md" in x["path"]][0]
assert r["review_status"] == "unreviewed"
assert r["source_file"] == "10-originals/docx/sample.docx"
'
}
