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

_claude_project_scope() {
  local target="$SB_VAULT_DIR/.mcp.json"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run sb_python "$SB_INSTALLER_ROOT/lib/py/merge_mcp_json.py" "$target" "$SB_VAULT_DIR"
    report_add "claude-mcp-project" "configured" "dry-run"
    return 0
  fi
  [ -e "$target" ] && backup_file "$target" >/dev/null
  if sb_python "$SB_INSTALLER_ROOT/lib/py/merge_mcp_json.py" "$target" "$SB_VAULT_DIR"; then
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
  local out
  if out="$(claude mcp add --scope user second-brain "$sb_cmd" 2>&1)"; then
    report_add "claude-mcp-user:second-brain" "configured" ""
  elif claude mcp list 2>/dev/null | grep -q "second-brain"; then
    report_add "claude-mcp-user:second-brain" "verified" "already registered"
  else
    report_add "claude-mcp-user:second-brain" "FAILED" "$out"
  fi
  if out="$(claude mcp add --scope user basic-memory uvx basic-memory mcp 2>&1)"; then
    report_add "claude-mcp-user:basic-memory" "configured" ""
  elif claude mcp list 2>/dev/null | grep -q "basic-memory"; then
    report_add "claude-mcp-user:basic-memory" "verified" "already registered"
  else
    report_add "claude-mcp-user:basic-memory" "FAILED" "$out"
  fi
  return 0
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
