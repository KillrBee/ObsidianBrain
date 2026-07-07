#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() { test_env_setup; }
teardown() { test_env_teardown; }

@test "repair restores a deleted script and a deleted config" {
  install_default
  [ "$status" -eq 0 ]
  rm "$VAULT/70-scripts/search/sb_search.py"
  rm "$VAULT/60-index-config/qmd/collections.yaml"

  run "$REPO_ROOT/install.sh" --repair --vault-dir "$VAULT" --skip-obsidian --claude-scope project
  [ "$status" -eq 0 ]
  [ -f "$VAULT/70-scripts/search/sb_search.py" ]
  [ -f "$VAULT/60-index-config/qmd/collections.yaml" ]
}

@test "upgrade replaces a user-modified script but backs it up first" {
  install_default
  [ "$status" -eq 0 ]
  echo "# local hack" >>"$VAULT/70-scripts/search/search_curated.sh"

  run "$REPO_ROOT/install.sh" --upgrade --vault-dir "$VAULT" --skip-obsidian --claude-scope project
  [ "$status" -eq 0 ]
  ! grep -q "local hack" "$VAULT/70-scripts/search/search_curated.sh"
  backup="$(ls "$VAULT"/70-scripts/search/search_curated.sh.bak.* | head -1)"
  grep -q "local hack" "$backup"
}

@test "upgrade leaves the conversion manifest alone" {
  install_default
  [ "$status" -eq 0 ]
  "$SB_PYTHON" - "$VAULT/60-index-config/manifests/conversion-manifest.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["documents"].append({"document_id": "keep-me", "source_checksum": "sha256:0"*1})
json.dump(d, open(p, "w"), indent=2)
EOF
  run "$REPO_ROOT/install.sh" --upgrade --vault-dir "$VAULT" --skip-obsidian --claude-scope project
  [ "$status" -eq 0 ]
  [ "$(json_get "$VAULT/60-index-config/manifests/conversion-manifest.json" 'any(e.get("document_id") == "keep-me" for e in d["documents"])')" = "True" ]
}
