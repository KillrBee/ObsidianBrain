#!/usr/bin/env bash
# mcp_claude.sh — Claude Code MCP configuration (spec §19).
# Scopes: project (vault-local .mcp.json — always safe), user (global via
# `claude mcp add`), both, or skip. Default: project.

step_mcp_claude() {
  if [ "${SB_NO_MCP:-0}" = "1" ]; then
    report_add "claude-mcp" "skipped" "--no-mcp"
    return 0
  fi
  local scope="${SB_CLAUDE_SCOPE:-project}"

  case "$scope" in
    skip)
      report_add "claude-mcp" "skipped" "scope=skip"
      return 0 ;;
    project|user|both) : ;;
    *) sb_warn "unknown --claude-scope '$scope', using project"; scope=project ;;
  esac

  local rc=0
  if [ "$scope" = "project" ] || [ "$scope" = "both" ]; then
    _claude_project_scope || rc=1
  fi
  if [ "$scope" = "user" ] || [ "$scope" = "both" ]; then
    _claude_user_scope || rc=1
  fi
  return $rc
}

# Resolved basic-memory binary (empty -> uvx fallback in the merge helpers).
# Using the installed binary avoids uvx re-resolving the environment at
# session start with a Python the dependency chain cannot build against.
sb_basic_memory_bin() { command -v basic-memory 2>/dev/null || true; }

_claude_project_scope() {
  local target="$SB_VAULT_DIR/.mcp.json"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run sb_python "$SB_INSTALLER_ROOT/lib/py/merge_mcp_json.py" "$target" "$SB_VAULT_DIR"
    report_add "claude-mcp-project" "configured" "dry-run"
    return 0
  fi
  [ -e "$target" ] && backup_file "$target" >/dev/null
  if sb_python "$SB_INSTALLER_ROOT/lib/py/merge_mcp_json.py" "$target" "$SB_VAULT_DIR" \
       --basic-memory-bin "$(sb_basic_memory_bin)"; then
    report_add "claude-mcp-project" "configured" "$target"
  else
    report_add "claude-mcp-project" "FAILED" "existing .mcp.json invalid or unwritable; left untouched"
    return 1
  fi
}

_claude_user_scope() {
  if ! sb_have claude; then
    report_add "claude-mcp-user" "skipped" "claude CLI not installed (no-op mode)"
    return 0
  fi
  local sb_cmd="$SB_VAULT_DIR/70-scripts/mcp/second-brain-mcp"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run claude mcp add --scope user second-brain "$sb_cmd"
    run claude mcp add --scope user basic-memory uvx basic-memory mcp
    report_add "claude-mcp-user" "configured" "dry-run"
    return 0
  fi
  local bm_bin
  bm_bin="$(sb_basic_memory_bin)"
  _claude_user_add "second-brain" "$sb_cmd"
  if [ -n "$bm_bin" ]; then
    _claude_user_add "basic-memory" "$bm_bin" mcp
  else
    _claude_user_add "basic-memory" uvx basic-memory mcp
  fi
  return 0
}

_claude_user_add() {
  # _claude_user_add <name> <command> [args...]
  local name="$1"; shift
  local out
  if out="$(claude mcp add --scope user "$name" "$@" 2>&1)"; then
    report_add "claude-mcp-user:$name" "configured" ""
    return 0
  fi
  if claude mcp list 2>/dev/null | grep -q "$name"; then
    report_add "claude-mcp-user:$name" "verified" "already registered"
    return 0
  fi
  case "$out" in
    *"enterprise policy"*|*"managed settings"*)
      # Org-managed Claude Code forbids user-scope servers. Not an installer
      # failure: project scope still works per repo.
      report_add "claude-mcp-user:$name" "skipped" \
        "blocked by enterprise policy — add per-project .mcp.json entries, or ask IT to allowlist; shell wrappers in 70-scripts/search work everywhere"
      ;;
    *)
      report_add "claude-mcp-user:$name" "FAILED" "$out"
      ;;
  esac
}

uninstall_mcp_claude() {
  local target="$SB_VAULT_DIR/.mcp.json"
  if [ -e "$target" ]; then
    backup_file "$target" >/dev/null
    if sb_python "$SB_INSTALLER_ROOT/lib/py/merge_mcp_json.py" "$target" "$SB_VAULT_DIR" --remove; then
      report_add "claude-mcp-project" "configured" "managed servers removed"
    else
      report_add "claude-mcp-project" "FAILED" "could not clean $target"
    fi
  fi
  if sb_have claude; then
    claude mcp remove --scope user second-brain >/dev/null 2>&1 || true
    claude mcp remove --scope user basic-memory >/dev/null 2>&1 || true
    report_add "claude-mcp-user" "configured" "managed servers removed (if present)"
  fi
}
