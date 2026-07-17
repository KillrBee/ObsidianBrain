#!/usr/bin/env bats
# Enterprise-managed Claude Code denies user-scope MCP registration. The
# installer must report that as a policy skip with guidance, not a failure.
load '../helpers/setup_vault'

setup() {
  test_env_setup
  # Stub claude CLI that refuses user-scope adds the way managed setups do.
  STUB_DIR="$SB_TEST_ROOT/stubs"; mkdir -p "$STUB_DIR"
  cat >"$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "mcp" ] && [ "$2" = "add" ]; then
  echo "Cannot add MCP server \"$4\": not allowed by enterprise policy" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$STUB_DIR/claude"
  export PATH="$STUB_DIR:$PATH"
}
teardown() { test_env_teardown; }

@test "enterprise-blocked user scope reports skipped, install still succeeds" {
  install_default --claude-scope both
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-mcp-user:second-brain: skipped"* ]]
  [[ "$output" == *"enterprise policy"* ]]
  ! grep -q "claude-mcp-user.*FAILED" <<<"$output"
  # Project scope still configured as the working fallback.
  [ -f "$VAULT/.mcp.json" ]
  report="$(ls "$VAULT"/80-logs/install-report-*.md | head -1)"
  grep -q "enterprise policy" "$report"
}

@test "genuinely unknown claude failure still reports FAILED" {
  cat >"$SB_TEST_ROOT/stubs/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "mcp" ] && [ "$2" = "add" ]; then
  echo "some unexpected explosion" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$SB_TEST_ROOT/stubs/claude"
  install_default --claude-scope both
  [[ "$output" == *"claude-mcp-user:second-brain"*"some unexpected explosion"* ]]
  [[ "$output" == *"error"* ]]
}
