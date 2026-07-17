#!/usr/bin/env bash
# agent_guides.sh — project the vault's memory-routing rules into user-scope
# agent config so agents in ANY project route durable memory to the vault:
#   ~/.claude/CLAUDE.md            managed markdown block (Claude Code)
#   ~/.codex/AGENTS.md             managed markdown block (Codex)
#   ~/.claude/skills/second-brain/ the second-brain skill
# User content outside the managed markers is never touched; every modified
# file is backed up first. Opt out with --no-agent-guides.

_render_guide_block() {
  # Render the user-scope block to a temp file; echoes its path.
  local tmp
  tmp="$(mktemp -t sb-guide-block)"
  render_template "$SB_INSTALLER_ROOT/payload/config/agent-guides/user-scope-block.md.tmpl" >"$tmp"
  printf '%s\n' "$tmp"
}

_merge_guide_into() {
  # _merge_guide_into <component> <target-md> <block-file>
  local component="$1" target="$2" block="$3"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run sb_python "$SB_INSTALLER_ROOT/lib/py/merge_managed_md.py" "$target" "$block"
    report_add "$component" "configured" "dry-run"
    return 0
  fi
  [ -e "$target" ] && backup_file "$target" >/dev/null
  if sb_python "$SB_INSTALLER_ROOT/lib/py/merge_managed_md.py" "$target" "$block"; then
    report_add "$component" "configured" "$target"
  else
    report_add "$component" "FAILED" "could not update $target"
    return 1
  fi
}

step_agent_guides() {
  if [ "${SB_NO_AGENT_GUIDES:-0}" = "1" ]; then
    report_add "agent-guides" "skipped" "--no-agent-guides"
    return 0
  fi

  local block rc=0
  block="$(_render_guide_block)"

  # Claude Code: user-scope CLAUDE.md + the second-brain skill.
  if sb_have claude || [ -d "$HOME/.claude" ]; then
    _merge_guide_into "agent-guides:claude" "$HOME/.claude/CLAUDE.md" "$block" || rc=1
    _install_skill || rc=1
  else
    report_add "agent-guides:claude" "skipped" "Claude Code not detected (no-op mode)"
  fi

  # Codex: user-scope AGENTS.md.
  if sb_have codex || [ "${SB_FORCE_CODEX:-0}" = "1" ]; then
    _merge_guide_into "agent-guides:codex" "$HOME/.codex/AGENTS.md" "$block" || rc=1
  else
    report_add "agent-guides:codex" "skipped" "codex CLI not installed (no-op mode)"
  fi

  rm -f "$block"
  return $rc
}

_install_skill() {
  # The skill template carries {{VAULT_DIR}} placeholders so the installed
  # copy holds real, runnable command paths for this machine.
  local src="$SB_INSTALLER_ROOT/payload/config/skills/second-brain/SKILL.md"
  local dest="$HOME/.claude/skills/second-brain/SKILL.md"
  if [ "${SB_DRY_RUN:-0}" = "1" ]; then
    run cp "$src" "$dest"
    report_add "agent-guides:skill" "configured" "dry-run"
    return 0
  fi
  local rendered
  rendered="$(mktemp -t sb-skill)"
  render_template "$src" >"$rendered"
  if [ -e "$dest" ]; then
    if [ "$(_sha256 "$dest")" = "$(_sha256 "$rendered")" ]; then
      rm -f "$rendered"
      report_add "agent-guides:skill" "verified" "second-brain skill up to date"
      return 0
    fi
    backup_file "$dest" >/dev/null
  fi
  write_file "$dest" 0644 <"$rendered" || { rm -f "$rendered"; return 1; }
  rm -f "$rendered"
  report_add "agent-guides:skill" "installed" "$dest"
}

uninstall_agent_guides() {
  local target
  for target in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
    [ -e "$target" ] || continue
    backup_file "$target" >/dev/null
    if sb_python "$SB_INSTALLER_ROOT/lib/py/merge_managed_md.py" "$target" /dev/null --remove; then
      report_add "agent-guides" "configured" "managed block removed from $target"
    else
      report_add "agent-guides" "FAILED" "could not clean $target"
    fi
  done
  if [ -d "$HOME/.claude/skills/second-brain" ]; then
    rm -rf "$HOME/.claude/skills/second-brain"
    report_add "agent-guides:skill" "configured" "second-brain skill removed"
  fi
}
