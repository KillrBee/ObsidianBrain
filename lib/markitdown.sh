#!/usr/bin/env bash
# markitdown.sh — MarkItDown CLI + the vault-side Python environment.

# uv_tool_install <spec> <bin> — install a Python CLI tool via uv (pipx fallback).
uv_tool_install() {
  local spec="$1" bin="$2"
  if sb_have uv; then
    run uv tool install --quiet "$spec" && return 0
    # Already installed via uv tool -> upgrade path keeps it fresh.
    run uv tool upgrade --quiet "$bin" && return 0
    return 1
  elif sb_have pipx; then
    run pipx install "$spec" >/dev/null 2>&1 || run pipx upgrade "$bin" >/dev/null 2>&1
    return $?
  fi
  return 1
}

step_markitdown() {
  if [ "${SB_SKIP_TOOLS:-0}" = "1" ]; then
    report_add "markitdown" "skipped" "SB_SKIP_TOOLS=1"
    return 0
  fi
  local extras="pdf,docx,pptx,xlsx"
  [ "${SB_WITH_TRANSCRIPTION:-0}" = "1" ] && extras="$extras,audio-transcription"

  if sb_have markitdown; then
    report_add "markitdown" "verified" "$(command -v markitdown)"
    return 0
  fi
  if uv_tool_install "markitdown[$extras]" markitdown; then
    report_add "markitdown" "installed" "extras: $extras"
  else
    return 1
  fi
}

# Vault-side venv for retrieval/MCP scripts: pyyaml, jsonschema, mcp.
step_python_env() {
  local venv="$SB_VAULT_DIR/70-scripts/.venv"
  if [ "${SB_SKIP_TOOLS:-0}" = "1" ]; then
    report_add "python-env" "skipped" "SB_SKIP_TOOLS=1 (scripts fall back to system python3)"
    return 0
  fi
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run uv venv "$venv"
    run uv pip install --python "$venv/bin/python" pyyaml jsonschema "mcp>=1.2"
    report_add "python-env" "installed" "dry-run"
    return 0
  fi
  if [ ! -x "$venv/bin/python" ]; then
    if sb_have uv; then
      uv venv --quiet "$venv" || return 1
    else
      python3 -m venv "$venv" || return 1
    fi
  fi
  if sb_have uv; then
    uv pip install --quiet --python "$venv/bin/python" pyyaml jsonschema "mcp>=1.2" || return 1
  else
    "$venv/bin/python" -m pip install --quiet pyyaml jsonschema "mcp>=1.2" || return 1
  fi
  report_add "python-env" "installed" "$venv (pyyaml, jsonschema, mcp)"
}
