#!/usr/bin/env bash
# Shared bats helpers: install into a temp vault with external tools stubbed.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
export REPO_ROOT

test_env_setup() {
  SB_TEST_ROOT="$(mktemp -d "${BATS_TMPDIR:-/tmp}/sbtest.XXXXXX")"
  export SB_TEST_ROOT
  export HOME="$SB_TEST_ROOT/home"
  mkdir -p "$HOME"
  export VAULT="$SB_TEST_ROOT/vault"

  # Skip anything that touches the real machine.
  export SB_SKIP_BREW=1 SB_SKIP_TOOLS=1 SB_SKIP_OBSIDIAN=1

  # Vault scripts run on the dev venv python (pyyaml/jsonschema/mcp installed).
  if [ -n "${SB_TEST_PYTHON:-}" ] && [ -x "${SB_TEST_PYTHON}" ]; then
    export SB_PYTHON="$SB_TEST_PYTHON"
  elif [ -x "$REPO_ROOT/.venv/bin/python" ]; then
    export SB_PYTHON="$REPO_ROOT/.venv/bin/python"
  else
    export SB_PYTHON="$(command -v python3)"
  fi
  if [ -x "$REPO_ROOT/.venv/bin/markitdown" ]; then
    export SB_MARKITDOWN_BIN="$REPO_ROOT/.venv/bin/markitdown"
  fi
}

test_env_teardown() {
  [ -n "${SB_TEST_ROOT:-}" ] && rm -rf "$SB_TEST_ROOT"
}

install_default() {
  run "$REPO_ROOT/install.sh" --mode default --vault-dir "$VAULT" \
    --skip-obsidian --claude-scope project "$@"
}

have_markitdown() {
  [ -n "${SB_MARKITDOWN_BIN:-}" ] && [ -x "$SB_MARKITDOWN_BIN" ]
}

# jq-style JSON probe using the test python (jq may be absent in minimal envs).
json_get() { # json_get <file-or-'-'> <python-expression over d>
  local src="$1" expr="$2"
  "$SB_PYTHON" -c "
import json, sys
src = sys.argv[1]
d = json.load(open(src) if src != '-' else sys.stdin)
print(eval(sys.argv[2], {'d': d}))
" "$src" "$expr"
}
