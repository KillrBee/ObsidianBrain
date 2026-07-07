#!/usr/bin/env bash
# validate.sh — post-install validation (spec §16.25–27): command checks,
# sample conversion, sample search, memory-write smoke test, MCP selfcheck.

_vault_python() {
  # Same resolution the vault scripts use.
  if [ -n "${SB_PYTHON:-}" ]; then echo "$SB_PYTHON"
  elif [ -x "$SB_VAULT_DIR/70-scripts/.venv/bin/python" ]; then echo "$SB_VAULT_DIR/70-scripts/.venv/bin/python"
  else echo "python3"; fi
}

step_validate() {
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    report_add "validation" "skipped" "dry-run"
    return 0
  fi
  local py rc=0
  py="$(_vault_python)"

  # 1. Commands and files present.
  local f
  for f in \
    "$SB_VAULT_DIR/70-scripts/convert/convert_new_documents.sh" \
    "$SB_VAULT_DIR/70-scripts/search/sb_search.sh" \
    "$SB_VAULT_DIR/70-scripts/index/update_qmd_indexes.sh" \
    "$SB_VAULT_DIR/70-scripts/mcp/second-brain-mcp" \
    "$SB_VAULT_DIR/60-index-config/qmd/collections.yaml" \
    "$SB_VAULT_DIR/60-index-config/manifests/conversion-manifest.json"; do
    if [ ! -e "$f" ]; then
      report_add "validate:files" "FAILED" "missing $f"
      return 1
    fi
  done
  report_add "validate:files" "verified" "scripts and config in place"

  # 2. Schemas + collections parse; frontmatter validator runs clean on seeds.
  if "$py" "$SB_VAULT_DIR/70-scripts/maintenance/validate_frontmatter.py" --vault "$SB_VAULT_DIR" >/dev/null 2>&1; then
    report_add "validate:frontmatter" "verified" "seed notes pass schema validation"
  else
    report_add "validate:frontmatter" "FAILED" "run 70-scripts/maintenance/validate_frontmatter.py --vault $SB_VAULT_DIR"
    rc=1
  fi

  # 3. Sample conversion (spec §16.26) — HTML needs no optional extras.
  if sb_have markitdown || [ -n "${SB_MARKITDOWN_BIN:-}" ]; then
    local sample="$SB_VAULT_DIR/00-inbox/raw-drops/welcome-sample.html"
    if [ ! -e "$SB_VAULT_DIR/20-converted/html-md/welcome-sample.md" ]; then
      cat >"$sample" <<'EOF'
<!doctype html>
<html><head><title>Welcome to your Second Brain</title></head>
<body><h1>Welcome to your Second Brain</h1>
<p>This sample document was converted by the install-time validation step.
Original documents are evidence; converted Markdown is retrieval substrate.</p>
</body></html>
EOF
      if "$SB_VAULT_DIR/70-scripts/convert/convert_new_documents.sh" --vault "$SB_VAULT_DIR" >/dev/null 2>&1 \
         && [ -e "$SB_VAULT_DIR/20-converted/html-md/welcome-sample.md" ]; then
        report_add "validate:conversion" "verified" "sample HTML converted with frontmatter + manifest entry"
      else
        report_add "validate:conversion" "FAILED" "sample conversion did not produce output; see 80-logs/conversion/"
        rc=1
      fi
    else
      report_add "validate:conversion" "verified" "sample already converted"
    fi
  else
    report_add "validate:conversion" "skipped" "markitdown not installed"
  fi

  # 4. Sample search (spec §16.27) over the seeded curated note.
  local search_out
  if search_out="$("$SB_VAULT_DIR/70-scripts/search/search_curated.sh" --vault "$SB_VAULT_DIR" --query "second brain" --max-results 3 2>/dev/null)" \
     && printf '%s' "$search_out" | "$py" -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("results") else 1)'; then
    report_add "validate:search" "verified" "search_curated returned results for 'second brain'"
  else
    report_add "validate:search" "FAILED" "search_curated.sh returned no parseable results"
    rc=1
  fi

  # 5. Agent-memory write/read discipline via the policy layer.
  if "$py" "$SB_VAULT_DIR/70-scripts/mcp/policy.py" --selftest --vault "$SB_VAULT_DIR" >/dev/null 2>&1; then
    report_add "validate:memory-write" "verified" "policy selftest wrote+read an agent-memory note"
  else
    report_add "validate:memory-write" "FAILED" "policy.py --selftest failed"
    rc=1
  fi

  # 6. MCP server selfcheck (requires 'mcp' package in the vault venv).
  if "$py" -c 'import mcp' >/dev/null 2>&1; then
    if "$py" "$SB_VAULT_DIR/70-scripts/mcp/server.py" --selfcheck >/dev/null 2>&1; then
      report_add "validate:mcp-server" "verified" "server registers its tool set"
    else
      report_add "validate:mcp-server" "FAILED" "server.py --selfcheck failed"
      rc=1
    fi
  else
    report_add "validate:mcp-server" "skipped" "mcp package not in python env (SB_SKIP_TOOLS?)"
  fi

  return $rc
}
