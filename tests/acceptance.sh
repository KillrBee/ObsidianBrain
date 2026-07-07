#!/usr/bin/env bash
# acceptance.sh — walk the spec §24 success criteria on a REAL machine.
# Unlike the bats suite this uses real installed tools (brew, markitdown,
# basic-memory, claude/codex CLIs when present). Safe default: a throwaway
# vault; pass --vault-dir ~/SecondBrain for the real thing.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT="${1:-}"
case "$VAULT" in
  --vault-dir) VAULT="${2:?}" ;;
  --vault-dir=*) VAULT="${VAULT#*=}" ;;
  *) VAULT="$(mktemp -d)/SecondBrain" ;;
esac

PASS=0 FAIL=0
check() { # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS %s\n' "$desc"; PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n' "$desc"; FAIL=$((FAIL + 1))
  fi
}

# Python scripts run on the vault's own interpreter (venv when present).
vpy() {
  if [ -x "$VAULT/70-scripts/.venv/bin/python" ]; then
    "$VAULT/70-scripts/.venv/bin/python" "$@"
  else
    python3 "$@"
  fi
}

echo "Acceptance run against: $VAULT"
echo

# 1. One command creates the stack.
check "1. installer completes" "$REPO_ROOT/install.sh" --mode default --vault-dir "$VAULT"

# 2. Obsidian can open the vault (structure exists; opening is manual).
check "2. vault structure valid" test -d "$VAULT/30-curated/decisions"

# 3-5. Conversion pipeline over dropped files with valid frontmatter.
for f in sample.pdf sample.docx sample.pptx sample.xlsx; do
  cp "$REPO_ROOT/tests/fixtures/$f" "$VAULT/00-inbox/raw-drops/" 2>/dev/null || true
done
check "3-4. conversion pipeline converts drops" "$VAULT/70-scripts/convert/convert_new_documents.sh"
check "5. converted frontmatter validates" vpy "$VAULT/70-scripts/maintenance/validate_frontmatter.py" --vault "$VAULT" --path 20-converted

# 6. Separate collection search — results must be NON-empty.
assert_hits() { # assert_hits <wrapper> <query>
  "$VAULT/70-scripts/search/$1" --query "$2" \
    | vpy -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["results"] else 1)'
}
check "6a. curated search returns hits" assert_hits search_curated.sh "second brain"
check "6b. sources search returns hits" assert_hits search_sources.sh "sample"

# 7. Basic Memory write/retrieve (via our policy layer + basic-memory CLI if present).
check "7. agent memory write/read" vpy "$VAULT/70-scripts/mcp/policy.py" --selftest --vault "$VAULT"

# 8-9. MCP configured for Claude Code / Codex.
check "8. claude .mcp.json present" test -f "$VAULT/.mcp.json"
if command -v codex >/dev/null 2>&1; then
  check "9. codex managed block present" grep -q "second-brain managed block" "$HOME/.codex/config.toml"
else
  echo "SKIP 9. codex CLI not installed"
fi

# 10-11. Context pack without whole-vault reads.
check "10. context pack builds" vpy "$VAULT/70-scripts/context/build_context_pack.py" --vault "$VAULT" --topic "second brain" --max-tokens 3000
check "11. access log shows scoped tools only" sh -c "! grep -q read_all '$VAULT/80-logs/agent-access/agent-access.jsonl'"

# 12. Originals untouched (checksums match manifest).
check "12. originals match manifest checksums" vpy "$VAULT/70-scripts/maintenance/checksum_inventory.py" --vault "$VAULT"

# 13. Git tracks curated/config/scripts.
check "13. git history exists" git -C "$VAULT" rev-parse HEAD

# 14. Install report exists.
check "14. install report written" sh -c "ls '$VAULT'/80-logs/install-report-*.md"

echo
echo "acceptance: $PASS passed, $FAIL failed (vault: $VAULT)"
[ "$FAIL" -eq 0 ]
