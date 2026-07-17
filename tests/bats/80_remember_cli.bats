#!/usr/bin/env bats
# Script-mode memory writes: remember.sh must give MCP-parity behavior
# (dedup guard, unreviewed stamping) from any working directory.
load '../helpers/setup_vault'

setup() {
  test_env_setup
  install_default
  [ "$status" -eq 0 ]
  REMEMBER="$VAULT/70-scripts/memory/remember.sh"
  cd "$SB_TEST_ROOT"   # deliberately NOT the vault
}
teardown() { test_env_teardown; }

@test "observe creates an unreviewed entity note from any cwd" {
  run "$REMEMBER" observe "Canonical Contacts" "survivorship picks preferred values" --confidence high
  [ "$status" -eq 0 ]
  echo "$output" | "$SB_PYTHON" -c 'import json,sys; d=json.load(sys.stdin); assert d["review_status"]=="unreviewed", d'
  note="$VAULT/40-agent-memory/observations/canonical-contacts.md"
  [ -f "$note" ]
  grep -q "review_status: unreviewed" "$note"
  grep -q "survivorship picks preferred values" "$note"

  # Second observation appends to the SAME note.
  run "$REMEMBER" observe "Canonical Contacts" "second fact"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- \[' "$note")" = "2" ]
}

@test "relate writes wikilinked relation lines" {
  run "$REMEMBER" relate "Canonical Contacts" derived_from "Source Projections"
  [ "$status" -eq 0 ]
  note="$VAULT/40-agent-memory/relations/canonical-contacts.md"
  grep -q '\*\*derived_from\*\*' "$note"
  grep -q '\[\[source-projections\]\]' "$note"
}

@test "note dedup refuses with exit 3 and names the existing note; --force overrides" {
  run "$REMEMBER" note 40-agent-memory/project-memory/rollout-status.md \
    "$(printf -- '---\ntitle: Introhive rollout status\n---\nPhase two underway.')"
  [ "$status" -eq 0 ]

  run "$REMEMBER" note 40-agent-memory/project-memory/rollout-status-new.md \
    "$(printf -- '---\ntitle: Introhive rollout\n---\nPhase two of the rollout.')"
  [ "$status" -eq 3 ]
  [[ "$output" == *"rollout-status.md"* ]]

  run "$REMEMBER" note 40-agent-memory/project-memory/rollout-status-new.md \
    "$(printf -- '---\ntitle: Introhive rollout\n---\nPhase two of the rollout.')" --force
  [ "$status" -eq 0 ]
}

@test "curated writes are refused with exit 2" {
  run "$REMEMBER" note 30-curated/concepts/hack.md "nope"
  [ "$status" -eq 2 ]
  [[ "$output" == *"policy"* ]]
}

@test "review tags a note; stdin content works for note" {
  echo "Fact from stdin." | "$REMEMBER" note 40-agent-memory/observations/stdin-note.md -
  grep -q "Fact from stdin." "$VAULT/40-agent-memory/observations/stdin-note.md"

  run "$REMEMBER" review 40-agent-memory/observations/stdin-note.md
  [ "$status" -eq 0 ]
  grep -q "review-requested" "$VAULT/40-agent-memory/observations/stdin-note.md"
}

@test "summarize writes an unreviewed extractive draft into agent memory" {
  run "$REMEMBER" summarize 30-curated/concepts/second-brain-overview.md
  [ "$status" -eq 0 ]
  out_path="$(echo "$output" | "$SB_PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["path"])')"
  [[ "$out_path" == 40-agent-memory/* ]]
  grep -q "review_status: unreviewed" "$VAULT/$out_path"
  grep -q "second-brain-overview" "$VAULT/$out_path"
}
