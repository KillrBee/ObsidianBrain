#!/usr/bin/env bash
# sb_common.sh — shared plumbing for vault-side shell scripts.
# Sourced with:  . "$(dirname "$0")/../lib/sb_common.sh"

# Vault root: SB_VAULT_DIR env wins; otherwise derived from this file's
# location (<vault>/70-scripts/lib/sb_common.sh). Scripts that accept a
# --vault flag overwrite SB_VAULT_ROOT after parsing.
_SB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB_SCRIPTS_ROOT="$(dirname "$_SB_LIB_DIR")"
SB_VAULT_ROOT="${SB_VAULT_DIR:-$(dirname "$SB_SCRIPTS_ROOT")}"

sb_err() { printf 'error: %s\n' "$*" >&2; }

# Python interpreter for vault tooling: SB_PYTHON > vault venv > python3.
sb_python_bin() {
  if [ -n "${SB_PYTHON:-}" ]; then
    printf '%s\n' "$SB_PYTHON"
  elif [ -x "$SB_SCRIPTS_ROOT/.venv/bin/python" ]; then
    printf '%s\n' "$SB_SCRIPTS_ROOT/.venv/bin/python"
  else
    printf '%s\n' "python3"
  fi
}

sb_python() {
  "$(sb_python_bin)" "$@"
}

sb_require_vault() {
  if [ ! -d "$SB_VAULT_ROOT/60-index-config" ]; then
    sb_err "not a SecondBrain vault: $SB_VAULT_ROOT (missing 60-index-config)"
    exit 1
  fi
}
