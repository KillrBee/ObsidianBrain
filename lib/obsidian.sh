#!/usr/bin/env bash
# obsidian.sh — install Obsidian (cask) or print manual instructions (spec §16.8).

step_obsidian() {
  if [ "${SB_SKIP_OBSIDIAN:-0}" = "1" ]; then
    report_add "obsidian" "skipped" "--skip-obsidian"
    return 0
  fi
  if [ -d "/Applications/Obsidian.app" ] || [ -d "$HOME/Applications/Obsidian.app" ]; then
    report_add "obsidian" "verified" "Obsidian.app present"
    return 0
  fi
  if [ "${SB_SKIP_BREW:-0}" = "1" ]; then
    report_add "obsidian" "skipped" "SB_SKIP_BREW=1"
    return 0
  fi
  if brew_ensure obsidian --cask; then
    return 0
  fi
  # Automated install not permitted / failed: degrade to instructions.
  sb_warn "Automated Obsidian install failed."
  sb_info "Install manually from https://obsidian.md/download, then open"
  sb_info "$SB_VAULT_DIR as a vault (Open folder as vault)."
  report_add "obsidian" "skipped" "manual install required — see instructions above"
  return 0
}
