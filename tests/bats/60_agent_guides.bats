#!/usr/bin/env bats
load '../helpers/setup_vault'

BEGIN_MARK='<!-- >>> second-brain managed block (do not edit inside) >>> -->'

setup() {
  test_env_setup
  mkdir -p "$HOME/.claude"        # deterministic Claude Code detection
  export SB_FORCE_CODEX=1         # deterministic Codex path
  export SB_CODEX_CONFIG="$HOME/.codex/config.toml"
}
teardown() { test_env_teardown; }

@test "install writes managed blocks, skill, and vault AGENTS.md" {
  install_default
  [ "$status" -eq 0 ]
  grep -qF "$BEGIN_MARK" "$HOME/.claude/CLAUDE.md"
  grep -q "SecondBrain memory routing" "$HOME/.claude/CLAUDE.md"
  grep -qF "$VAULT" "$HOME/.claude/CLAUDE.md"
  grep -qF "$BEGIN_MARK" "$HOME/.codex/AGENTS.md"
  [ -f "$HOME/.claude/skills/second-brain/SKILL.md" ]
  grep -q "name: second-brain" "$HOME/.claude/skills/second-brain/SKILL.md"
  # Skill is rendered with this machine's real vault path — runnable commands.
  grep -qF "$VAULT/70-scripts/memory/remember.sh" "$HOME/.claude/skills/second-brain/SKILL.md"
  ! grep -q "{{VAULT_DIR}}" "$HOME/.claude/skills/second-brain/SKILL.md"
  [ -f "$VAULT/AGENTS.md" ]
  grep -q "trust-layered knowledge base" "$VAULT/AGENTS.md"
}

@test "existing user CLAUDE.md content is preserved and backed up" {
  printf '# My own rules\nAlways use tabs.\n' >"$HOME/.claude/CLAUDE.md"
  install_default
  [ "$status" -eq 0 ]
  grep -q "Always use tabs." "$HOME/.claude/CLAUDE.md"
  grep -qF "$BEGIN_MARK" "$HOME/.claude/CLAUDE.md"
  ls "$HOME/.claude/CLAUDE.md".bak.* >/dev/null
}

@test "re-run refreshes the block without duplicating it" {
  install_default
  [ "$status" -eq 0 ]
  install_default
  [ "$status" -eq 0 ]
  [ "$(grep -cF "$BEGIN_MARK" "$HOME/.claude/CLAUDE.md")" = "1" ]
  [ "$(grep -cF "$BEGIN_MARK" "$HOME/.codex/AGENTS.md")" = "1" ]
}

@test "--no-agent-guides skips user-scope projection entirely" {
  install_default --no-agent-guides
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/CLAUDE.md" ]
  [ ! -e "$HOME/.codex/AGENTS.md" ]
  [ ! -e "$HOME/.claude/skills/second-brain/SKILL.md" ]
  [[ "$output" == *"agent-guides: skipped"* ]]
}

@test "uninstall removes blocks and skill but keeps user content" {
  printf '# Keep me\n' >"$HOME/.claude/CLAUDE.md"
  install_default
  [ "$status" -eq 0 ]
  run "$REPO_ROOT/install.sh" --uninstall --vault-dir "$VAULT"
  [ "$status" -eq 0 ]
  grep -q "Keep me" "$HOME/.claude/CLAUDE.md"
  ! grep -qF "$BEGIN_MARK" "$HOME/.claude/CLAUDE.md"
  ! grep -qF "$BEGIN_MARK" "$HOME/.codex/AGENTS.md"
  [ ! -e "$HOME/.claude/skills/second-brain" ]
}
