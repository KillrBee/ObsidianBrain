"""Policy layer: spec §11 boundaries actually hold."""
from __future__ import annotations

import pytest


def _policy():
    import policy
    return policy


@pytest.mark.parametrize("path", [
    "10-originals/pdf/evidence.pdf",
    "../../etc/passwd",
    "/etc/passwd",
    "70-scripts/mcp/server.py",
    "60-index-config/install-state.json",
    "~/.ssh/id_rsa",
])
def test_reads_outside_allowlist_rejected(scratch_vault, path):
    policy = _policy()
    with pytest.raises(policy.PolicyError):
        policy.check_read(scratch_vault, path)


@pytest.mark.parametrize("path", [
    "30-curated/concepts/x.md",          # curated is read-only for agents
    "20-converted/pdf-md/x.md",          # conversions owned by the pipeline
    "10-originals/pdf/x.pdf",
    "40-agent-memory/../30-curated/x.md",  # traversal into curated
    "40-agent-memory/notes.txt",         # non-markdown
])
def test_writes_outside_allowlist_rejected(scratch_vault, path):
    policy = _policy()
    with pytest.raises(policy.PolicyError):
        policy.check_write(scratch_vault, path)


def test_excluded_patterns_blocked_even_inside_allowed_areas(scratch_vault):
    policy = _policy()
    with pytest.raises(policy.PolicyError):
        policy.check_read(scratch_vault, "30-curated/concepts/credentials.md")


def test_memory_write_stamps_unreviewed(scratch_vault):
    policy = _policy()
    rel = "40-agent-memory/observations/test-note.md"
    out = policy.write_agent_memory_note(scratch_vault, rel, "An observation.", agent="test")
    assert out["review_status"] == "unreviewed"
    note = policy.read_note(scratch_vault, rel)
    assert note["frontmatter"]["doc_type"] == "agent_memory"
    assert note["frontmatter"]["review_status"] == "unreviewed"
    assert "An observation." in note["body"]


def test_memory_write_cannot_claim_reviewed(scratch_vault):
    policy = _policy()
    sneaky = "---\ntitle: sneaky\nreview_status: reviewed\nmemory_type: constraint\n---\nBody."
    rel = "40-agent-memory/constraints/sneaky.md"
    policy.write_agent_memory_note(scratch_vault, rel, sneaky, agent="test")
    note = policy.read_note(scratch_vault, rel)
    assert note["frontmatter"]["review_status"] == "unreviewed"
    assert note["frontmatter"]["memory_type"] == "constraint"  # rest preserved


def test_append_observation_and_relation_accumulate(scratch_vault):
    policy = _policy()
    for i in range(2):
        policy.append_observation(scratch_vault, "Canonical Contacts",
                                  f"observation {i}", "high", source="test")
    note = policy.read_note(scratch_vault, "40-agent-memory/observations/canonical-contacts.md")
    assert note["body"].count("- [") == 2
    assert "## Observations" in note["body"]

    policy.append_relation(scratch_vault, "Canonical Contacts", "derived_from",
                           "Source Projections", "medium")
    rel = policy.read_note(scratch_vault, "40-agent-memory/relations/canonical-contacts.md")
    assert "**derived_from**" in rel["body"]
    assert "[[source-projections]]" in rel["body"]


def test_mark_memory_for_review_tags(scratch_vault):
    policy = _policy()
    rel = "40-agent-memory/observations/tag-me.md"
    policy.write_agent_memory_note(scratch_vault, rel, "Note.", agent="test")
    out = policy.mark_memory_for_review(scratch_vault, rel)
    assert "review-requested" in out["tags"]


def test_summarize_sources_writes_unreviewed_draft(scratch_vault):
    policy = _policy()
    src = "30-curated/concepts/second-brain-overview.md"
    out = policy.summarize_sources(scratch_vault, [src])
    assert out["path"].startswith("40-agent-memory/")
    note = policy.read_note(scratch_vault, out["path"])
    assert note["frontmatter"]["review_status"] == "unreviewed"
    assert src in note["body"]

    with pytest.raises(policy.PolicyError):
        policy.summarize_sources(scratch_vault, [src], target_folder="30-curated/summaries")


def test_read_note_returns_frontmatter_and_body(scratch_vault):
    policy = _policy()
    note = policy.read_note(scratch_vault, "30-curated/concepts/second-brain-overview.md")
    assert note["frontmatter"]["trust_level"] == "human-reviewed"
    assert "Second Brain" in note["body"]


def test_selftest_passes(scratch_vault):
    policy = _policy()
    assert policy.selftest(scratch_vault) == 0
