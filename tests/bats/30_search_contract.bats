#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() {
  test_env_setup
  install_default
  [ "$status" -eq 0 ]

  # Seed notes with known frontmatter for filter tests.
  cat >"$VAULT/30-curated/concepts/dynamic-survivorship.md" <<'EOF'
---
title: "Dynamic Survivorship"
doc_type: curated_synthesis
created: "2026-07-01"
updated: "2026-07-01"
project: introhive
domain: [identity]
status: active
trust_level: human-reviewed
review_status: reviewed
source_files: []
confidence: high
supersedes: []
superseded_by:
tags: [identity-resolution]
---

# Dynamic Survivorship

Dynamic survivorship selects the currently preferred value while preserving
source evidence for identity resolution.
EOF
  cat >"$VAULT/30-curated/concepts/old-approach.md" <<'EOF'
---
title: "Old Survivorship Approach"
doc_type: curated_synthesis
created: "2025-01-01"
updated: "2025-01-01"
project: introhive
domain: [identity]
status: superseded
trust_level: human-reviewed
review_status: reviewed
source_files: []
confidence: low
supersedes: []
superseded_by: "30-curated/concepts/dynamic-survivorship.md"
tags: [identity-resolution]
---

# Old Survivorship Approach

Legacy survivorship notes about identity resolution.
EOF
  # A secret-looking file that must NEVER surface.
  printf -- '---\ntitle: creds\n---\nsurvivorship password hunter2\n' \
    >"$VAULT/30-curated/concepts/credentials.md"

  # Notes added outside the conversion pipeline need an index refresh before
  # an indexed backend can see them (no-op without qmd).
  "$VAULT/70-scripts/index/update_qmd_indexes.sh" --vault "$VAULT" >/dev/null 2>&1 || true
}
teardown() { test_env_teardown; }

@test "wrapper returns the full JSON contract" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "dynamic survivorship identity resolution"
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["query"] and d["collection"] == "curated"
assert d["backend"] in ("qmd", "ripgrep", "internal")
top = d["results"][0]
assert top["path"] == "30-curated/concepts/dynamic-survivorship.md", top
assert 0 < top["score"] <= 1
assert "survivorship" in top["snippet"].lower()
assert top["trust_level"] == "human-reviewed"
assert top["review_status"] == "reviewed"
'
}

@test "superseded notes rank below active ones" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "survivorship identity"
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
paths = [r["path"] for r in d["results"]]
active = paths.index("30-curated/concepts/dynamic-survivorship.md")
old = paths.index("30-curated/concepts/old-approach.md")
assert active < old, paths
'
}

@test "credential-pattern files never appear in results" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "survivorship password hunter2" --max-results 50
  [ "$status" -eq 0 ]
  [[ "$output" != *"credentials.md"* ]]
}

@test "project filter and status filter narrow results" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "survivorship" --project introhive --status active
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert len(d["results"]) == 1, d["results"]
assert d["results"][0]["path"].endswith("dynamic-survivorship.md")
'
  run "$VAULT/70-scripts/search/search_curated.sh" --query "survivorship" --project nonexistent
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | "$SB_PYTHON" -c 'import json,sys; print(len(json.load(sys.stdin)["results"]))')" = "0" ]
}

@test "max-results is capped at 50" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "survivorship" --max-results 500
  [ "$status" -eq 0 ]
}

@test "unknown collection errors cleanly" {
  run "$VAULT/70-scripts/search/sb_search.sh" --query x --collection bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown collection"* ]]
}

@test "collection scoping: decisions wrapper only searches decisions" {
  run "$VAULT/70-scripts/search/search_decisions.sh" --query "survivorship"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | "$SB_PYTHON" -c 'import json,sys; print(len(json.load(sys.stdin)["results"]))')" = "0" ]
  run "$VAULT/70-scripts/search/search_decisions.sh" --query "second brain stack"
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert all(r["path"].startswith("30-curated/decisions/") for r in d["results"])
assert d["results"], "seeded decision not found"
'
}

@test "searches append to the agent-access log" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "survivorship"
  [ "$status" -eq 0 ]
  [ -s "$VAULT/80-logs/agent-access/agent-access.jsonl" ]
  grep -q '"tool": "search"' "$VAULT/80-logs/agent-access/agent-access.jsonl"
}

@test "internal and auto backends agree on the contract shape" {
  for backend in auto internal; do
    run "$VAULT/70-scripts/search/sb_search.sh" --query "survivorship" --collection curated --backend "$backend"
    [ "$status" -eq 0 ]
    echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
for r in d["results"]:
    assert set(r) == {"path","title","score","snippet","trust_level","review_status","source_file"}, r
'
  done
}
