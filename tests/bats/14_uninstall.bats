#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() { test_env_setup; }
teardown() { test_env_teardown; }

@test "uninstall removes managed MCP entries but never the vault" {
  export SB_FORCE_CODEX=1   # exercise codex path even without the CLI
  export SB_CODEX_CONFIG="$HOME/.codex/config.toml"
  install_default
  [ "$status" -eq 0 ]
  [ -f "$SB_CODEX_CONFIG" ]

  run "$REPO_ROOT/install.sh" --uninstall --vault-dir "$VAULT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"was NOT touched"* ]]

  # Vault intact.
  [ -f "$VAULT/README.md" ]
  [ -d "$VAULT/30-curated" ]
  # Managed servers removed from project .mcp.json.
  if [ -f "$VAULT/.mcp.json" ]; then
    [ "$(json_get "$VAULT/.mcp.json" '"second-brain" in d.get("mcpServers", {})')" = "False" ]
  fi
  # Managed block removed from codex config.
  ! grep -q "second-brain managed block" "$SB_CODEX_CONFIG"
}
