#!/usr/bin/env bats
# Real-QMD backend tests. Skipped unless a qmd binary is available — set
# SB_QMD_BIN to an explicit binary or have qmd on PATH. XDG sandboxing in
# test_env_setup keeps registration away from real user config.
load '../helpers/setup_vault'

setup() {
  test_env_setup
  if [ -z "${SB_QMD_BIN:-}" ]; then
    if command -v qmd >/dev/null 2>&1; then
      export SB_QMD_BIN="$(command -v qmd)"
    else
      skip "qmd not available (npm install -g @tobilu/qmd, or set SB_QMD_BIN)"
    fi
  fi
  install_default
  [ "$status" -eq 0 ]
  run "$VAULT/70-scripts/index/update_qmd_indexes.sh" --vault "$VAULT" --register
  [ "$status" -eq 0 ]
}
teardown() { test_env_teardown; }

@test "qmd: collections registered under sb- prefix in sandboxed config" {
  [ -f "$XDG_CONFIG_HOME/qmd/index.yml" ]
  for c in curated decisions core-memory projects sources-converted context-packs; do
    grep -q "sb-$c" "$XDG_CONFIG_HOME/qmd/index.yml" || { echo "missing sb-$c"; false; }
  done
}

@test "qmd: backend=qmd returns the wrapper contract with vault-relative paths" {
  run "$VAULT/70-scripts/search/sb_search.sh" --query "second brain" --collection curated --backend qmd
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["backend"] == "qmd", d["backend"]
assert d["results"], "qmd returned no results"
for r in d["results"]:
    assert set(r) == {"path","title","score","snippet","trust_level","review_status","source_file"}, r
    assert not r["path"].startswith("qmd://"), r["path"]
paths = [r["path"] for r in d["results"]]
assert "30-curated/concepts/second-brain-overview.md" in paths, paths
'
}

@test "qmd: auto backend prefers qmd when registered" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "second brain"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | "$SB_PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["backend"])')" = "qmd" ]
}

@test "qmd: post-filters apply on the qmd path" {
  run "$VAULT/70-scripts/search/search_curated.sh" --query "second brain" --project nonexistent --backend qmd
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | "$SB_PYTHON" -c 'import json,sys; print(len(json.load(sys.stdin)["results"]))')" = "0" ]
}

@test "qmd: broken binary falls back to the internal backend on auto" {
  SB_QMD_BIN="/nonexistent/qmd" run "$VAULT/70-scripts/search/search_curated.sh" --query "second brain"
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c '
import json, sys
d = json.load(sys.stdin)
assert d["backend"] in ("ripgrep", "internal"), d["backend"]
assert d["results"], "fallback returned no results"
'
}

@test "qmd: uninstall removes only sb- collections" {
  # Add a non-managed user collection to the same sandboxed qmd config.
  userdir="$SB_TEST_ROOT/user-notes"; mkdir -p "$userdir"; echo "# note" >"$userdir/n.md"
  "$SB_QMD_BIN" collection add "$userdir" --name my-own >/dev/null 2>&1

  run "$REPO_ROOT/install.sh" --uninstall --vault-dir "$VAULT"
  [ "$status" -eq 0 ]
  ! grep -q "sb-curated" "$XDG_CONFIG_HOME/qmd/index.yml"
  grep -q "my-own" "$XDG_CONFIG_HOME/qmd/index.yml"
}
