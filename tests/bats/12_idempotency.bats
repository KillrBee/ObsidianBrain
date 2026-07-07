#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() { test_env_setup; }
teardown() { test_env_teardown; }

@test "second run reports verified/skipped only — no reinstalls, no failures" {
  install_default
  [ "$status" -eq 0 ]
  install_default
  [ "$status" -eq 0 ]
  [[ "$output" == *"payload: verified"* ]]
  ! grep -q 'FAILED' <<<"$output"
}

@test "user-edited vault files survive a re-run untouched" {
  install_default
  [ "$status" -eq 0 ]
  echo "MY CUSTOM NOTES" >>"$VAULT/README.md"
  sed_marker="user-was-here-$$"
  echo "# $sed_marker" >>"$VAULT/70-scripts/search/search_curated.sh"
  before_readme="$(shasum "$VAULT/README.md")"
  before_script="$(shasum "$VAULT/70-scripts/search/search_curated.sh")"

  install_default
  [ "$status" -eq 0 ]
  [ "$(shasum "$VAULT/README.md")" = "$before_readme" ]
  [ "$(shasum "$VAULT/70-scripts/search/search_curated.sh")" = "$before_script" ]
  [[ "$output" == *"preserving user-modified"* ]]
}

@test "user keys in .mcp.json survive a re-run" {
  install_default
  [ "$status" -eq 0 ]
  "$SB_PYTHON" - "$VAULT/.mcp.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["mcpServers"]["mine"] = {"command": "/my/tool"}
d["custom"] = 1
json.dump(d, open(p, "w"), indent=2)
EOF
  install_default
  [ "$status" -eq 0 ]
  [ "$(json_get "$VAULT/.mcp.json" '"mine" in d["mcpServers"] and d.get("custom") == 1')" = "True" ]
  [ "$(json_get "$VAULT/.mcp.json" '"second-brain" in d["mcpServers"]')" = "True" ]
}
