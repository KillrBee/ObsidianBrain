#!/usr/bin/env bash
# basic_memory.sh — Basic Memory install + project root pinned to
# 40-agent-memory (spec §20: agent memory stays out of curated folders).

step_basic_memory() {
  if [ "${SB_SKIP_TOOLS:-0}" = "1" ]; then
    report_add "basic-memory" "skipped" "SB_SKIP_TOOLS=1"
    return 0
  fi

  if ! sb_have basic-memory; then
    if uv_tool_install basic-memory basic-memory; then
      report_add "basic-memory" "installed" ""
    else
      report_add "basic-memory" "FAILED" "install failed; agent memory tools unavailable until installed"
      return 0   # optional-ish: do not block the rest of the install
    fi
  else
    report_add "basic-memory" "verified" "$(command -v basic-memory)"
  fi

  step_basic_memory_project
}

step_basic_memory_project() {
  local memory_root="$SB_VAULT_DIR/40-agent-memory"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run basic-memory project add second-brain "$memory_root"
    report_add "basic-memory-project" "configured" "dry-run"
    return 0
  fi
  if ! sb_have basic-memory; then
    report_add "basic-memory-project" "skipped" "basic-memory not installed"
    return 0
  fi
  # Idempotent registration: 'project add' errors if it exists; treat as verified.
  if basic-memory project add second-brain "$memory_root" >/dev/null 2>&1; then
    report_add "basic-memory-project" "configured" "second-brain -> $memory_root"
  elif basic-memory project list 2>/dev/null | grep -q "second-brain"; then
    report_add "basic-memory-project" "verified" "project already registered"
  else
    report_add "basic-memory-project" "FAILED" "could not register project (check 'basic-memory project add second-brain $memory_root')"
  fi
  # Record the intended root in our own config regardless, so the MCP entry
  # and any future repair can reconstruct it.
  state_set "basic_memory_root" "\"$memory_root\""
  return 0
}
