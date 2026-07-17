#!/usr/bin/env bash
# mcp_codex.sh — Codex MCP configuration (spec §18): backup, managed-section
# merge into ~/.codex/config.toml, TOML validation, preserve user settings.

step_mcp_codex() {
  if [ "${SB_NO_MCP:-0}" = "1" ]; then
    report_add "codex-mcp" "skipped" "--no-mcp"
    return 0
  fi
  if ! sb_have codex && [ "${SB_FORCE_CODEX:-0}" != "1" ]; then
    report_add "codex-mcp" "skipped" "codex CLI not installed (no-op mode)"
    return 0
  fi

  local target="${SB_CODEX_CONFIG:-$HOME/.codex/config.toml}"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run sb_python "$SB_INSTALLER_ROOT/lib/py/merge_codex_toml.py" "$target" "$SB_VAULT_DIR"
    report_add "codex-mcp" "configured" "dry-run"
    return 0
  fi

  [ -e "$target" ] && backup_file "$target" >/dev/null
  local rc=0
  sb_python "$SB_INSTALLER_ROOT/lib/py/merge_codex_toml.py" "$target" "$SB_VAULT_DIR" \
    --basic-memory-bin "$(sb_basic_memory_bin)" || rc=$?
  case "$rc" in
    0) report_add "codex-mcp" "configured" "managed block in $target" ;;
    2) report_add "codex-mcp" "FAILED" "existing config.toml is invalid TOML; left untouched" ; return 1 ;;
    3) report_add "codex-mcp" "FAILED" "merge would duplicate mcp_servers entries; left untouched" ; return 1 ;;
    *) report_add "codex-mcp" "FAILED" "unexpected error (rc=$rc)" ; return 1 ;;
  esac
}

uninstall_mcp_codex() {
  local target="${SB_CODEX_CONFIG:-$HOME/.codex/config.toml}"
  [ -e "$target" ] || return 0
  backup_file "$target" >/dev/null
  if sb_python "$SB_INSTALLER_ROOT/lib/py/merge_codex_toml.py" "$target" "$SB_VAULT_DIR" --remove; then
    report_add "codex-mcp" "configured" "managed block removed"
  else
    report_add "codex-mcp" "FAILED" "could not clean $target"
  fi
}
