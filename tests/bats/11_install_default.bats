#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() { test_env_setup; }
teardown() { test_env_teardown; }

@test "default install creates the full spec §5 tree" {
  install_default
  [ "$status" -eq 0 ]
  for d in \
    00-inbox/raw-drops 00-inbox/needs-triage \
    10-originals/pdf 10-originals/docx 10-originals/pptx 10-originals/xlsx \
    10-originals/html 10-originals/email 10-originals/audio 10-originals/images 10-originals/other \
    20-converted/pdf-md 20-converted/docx-md 20-converted/pptx-md 20-converted/xlsx-md \
    20-converted/html-md 20-converted/email-md 20-converted/transcript-md 20-converted/image-md 20-converted/other-md \
    30-curated/concepts 30-curated/decisions 30-curated/summaries 30-curated/people \
    30-curated/projects 30-curated/systems 30-curated/glossary 30-curated/patterns 30-curated/playbooks \
    40-agent-memory/daily 40-agent-memory/project-memory 40-agent-memory/constraints \
    40-agent-memory/preferences 40-agent-memory/observations 40-agent-memory/relations 40-agent-memory/lessons-learned \
    50-context-packs/active 50-context-packs/drafts 50-context-packs/archived \
    60-index-config/qmd 60-index-config/basic-memory 60-index-config/mcp 60-index-config/schemas 60-index-config/manifests \
    70-scripts/convert 70-scripts/index 70-scripts/search 70-scripts/context 70-scripts/maintenance 70-scripts/mcp \
    80-logs/conversion 80-logs/indexing 80-logs/agent-access 80-logs/errors \
    90-archive; do
    [ -d "$VAULT/$d" ] || { echo "missing dir: $d"; false; }
  done
  [ -f "$VAULT/README.md" ]
  [ -f "$VAULT/MEMORY.md" ]
  [ -f "$VAULT/40-agent-memory/MEMORY.md" ]
}

@test "git repo initialized with gitignore and an initial commit" {
  install_default
  [ "$status" -eq 0 ]
  [ -d "$VAULT/.git" ]
  [ -f "$VAULT/.gitignore" ]
  grep -q '.obsidian/workspace' "$VAULT/.gitignore"
  grep -q '10-originals' "$VAULT/.gitignore"
  git -C "$VAULT" rev-parse HEAD >/dev/null
}

@test "payload scripts installed and executable; manifest seeded" {
  install_default
  [ "$status" -eq 0 ]
  [ -x "$VAULT/70-scripts/convert/convert_new_documents.sh" ]
  [ -x "$VAULT/70-scripts/search/search_curated.sh" ]
  [ -x "$VAULT/70-scripts/mcp/second-brain-mcp" ]
  [ -f "$VAULT/60-index-config/qmd/collections.yaml" ]
  # Manifest is valid; at most the installer's own welcome-sample conversion
  # is in it (present when markitdown was available during validation).
  [ "$(json_get "$VAULT/60-index-config/manifests/conversion-manifest.json" 'isinstance(d["documents"], list) and all(e["source_path"].startswith("10-originals/") for e in d["documents"])')" = "True" ]
}

@test "install report written, listing installed and skipped steps" {
  install_default
  [ "$status" -eq 0 ]
  report="$(ls "$VAULT"/80-logs/install-report-*.md | head -1)"
  [ -f "$report" ]
  grep -q '| vault-tree |' "$report"
  grep -q 'skipped' "$report"
  ! grep -q 'FAILED' "$report"
}

@test "project .mcp.json written with both managed servers" {
  install_default
  [ "$status" -eq 0 ]
  [ -f "$VAULT/.mcp.json" ]
  [ "$(json_get "$VAULT/.mcp.json" '"second-brain" in d["mcpServers"] and "basic-memory" in d["mcpServers"]')" = "True" ]
}

@test "sample search finds the seeded curated note" {
  install_default
  [ "$status" -eq 0 ]
  run "$VAULT/70-scripts/search/search_curated.sh" --query "second brain" --max-results 3
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["collection"] == "curated"
assert d["results"], "no results"
r = d["results"][0]
assert r["trust_level"] == "human-reviewed"
assert set(r) >= {"path","title","score","snippet","trust_level","review_status","source_file"}
'
}

@test "validation step passes on a fresh install" {
  install_default
  [ "$status" -eq 0 ]
  [[ "$output" == *"validate:frontmatter: verified"* ]]
  [[ "$output" == *"validate:search: verified"* ]]
  [[ "$output" == *"validate:memory-write: verified"* ]]
}
