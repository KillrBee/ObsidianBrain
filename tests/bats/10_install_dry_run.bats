#!/usr/bin/env bats
load '../helpers/setup_vault'

setup() { test_env_setup; }
teardown() { test_env_teardown; }

@test "dry-run exits 0 and prints a plan" {
  run "$REPO_ROOT/install.sh" --dry-run --vault-dir "$VAULT" --skip-obsidian
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [[ "$output" == *"Vault directory structure"* ]]
  [[ "$output" == *"Installation report"* ]]
}

@test "dry-run performs zero filesystem writes at the target" {
  run "$REPO_ROOT/install.sh" --dry-run --vault-dir "$VAULT" --skip-obsidian
  [ "$status" -eq 0 ]
  [ ! -e "$VAULT" ]
  # No codex config, no claude config appeared in the fake HOME either.
  [ ! -e "$HOME/.codex/config.toml" ]
}

@test "unknown flag fails with usage" {
  run "$REPO_ROOT/install.sh" --bogus
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown option"* ]]
}
