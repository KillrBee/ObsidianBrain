#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() {
  test_env_setup
  export SB_FORCE_CODEX=1
  export SB_CODEX_CONFIG="$HOME/.codex/config.toml"
}
teardown() { test_env_teardown; }

@test "codex: fresh config gets the managed block and valid TOML" {
  install_default
  [ "$status" -eq 0 ]
  [ -f "$SB_CODEX_CONFIG" ]
  grep -q "second-brain managed block" "$SB_CODEX_CONFIG"
  "$SB_PYTHON" -c "import tomllib; d=tomllib.load(open('$SB_CODEX_CONFIG','rb')); assert 'second-brain' in d['mcp_servers'] and 'basic-memory' in d['mcp_servers']"
}

@test "codex: existing user settings are preserved and backed up" {
  mkdir -p "$HOME/.codex"
  cp "$REPO_ROOT/tests/fixtures/codex-config-existing.toml" "$SB_CODEX_CONFIG"
  install_default
  [ "$status" -eq 0 ]
  grep -q 'model = "gpt-5-codex"' "$SB_CODEX_CONFIG"
  grep -q 'existing-server' "$SB_CODEX_CONFIG"
  grep -q "second-brain managed block" "$SB_CODEX_CONFIG"
  ls "$SB_CODEX_CONFIG".bak.* >/dev/null
  "$SB_PYTHON" -c "
import tomllib
d = tomllib.load(open('$SB_CODEX_CONFIG','rb'))
assert d['model'] == 'gpt-5-codex'
assert 'existing-server' in d['mcp_servers']
assert 'second-brain' in d['mcp_servers']
"
}

@test "codex: managed block is replaced, not duplicated, on re-run" {
  install_default
  [ "$status" -eq 0 ]
  install_default
  [ "$status" -eq 0 ]
  [ "$(grep -c 'second-brain managed block (do not edit inside)' "$SB_CODEX_CONFIG")" = "1" ]
}

@test "codex: invalid existing TOML fails the step and leaves the file untouched" {
  mkdir -p "$HOME/.codex"
  printf 'this is [not valid toml\n' >"$SB_CODEX_CONFIG"
  before="$(shasum "$SB_CODEX_CONFIG")"
  install_default
  [ "$status" -eq 1 ]   # installer exits 1 because a step failed
  [[ "$output" == *"codex-mcp"*"invalid TOML"* ]]
  # File content unchanged (the backup copy is expected; original preserved).
  [ "$(shasum "$SB_CODEX_CONFIG")" = "$before" ]
  # Everything else still installed fine.
  [ -f "$VAULT/README.md" ]
}

@test "codex: user-defined second-brain server outside the block aborts the merge" {
  mkdir -p "$HOME/.codex"
  cat >"$SB_CODEX_CONFIG" <<'EOF'
[mcp_servers.second-brain]
command = "/user/custom/second-brain"
EOF
  install_default
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
  grep -q "/user/custom/second-brain" "$SB_CODEX_CONFIG"
}

@test "claude: existing .mcp.json keys survive the merge" {
  mkdir -p "$VAULT"
  cp "$REPO_ROOT/tests/fixtures/mcp-json-existing.json" "$VAULT/.mcp.json"
  install_default
  [ "$status" -eq 0 ]
  [ "$(json_get "$VAULT/.mcp.json" 'd["mcpServers"]["existing"]["args"] == ["--keep-me"] and d["userSetting"] == "preserve-this"')" = "True" ]
  [ "$(json_get "$VAULT/.mcp.json" '"second-brain" in d["mcpServers"]')" = "True" ]
}

@test "claude: --no-mcp skips both clients" {
  install_default --no-mcp
  [ "$status" -eq 0 ]
  [ ! -f "$VAULT/.mcp.json" ]
  [ ! -f "$SB_CODEX_CONFIG" ]
  [[ "$output" == *"claude-mcp: skipped"* ]]
  [[ "$output" == *"codex-mcp: skipped"* ]]
}
