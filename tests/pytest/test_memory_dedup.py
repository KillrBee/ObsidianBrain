"""Anti-duplication guard: near-duplicate memory creation is refused,
updates always pass, maintenance report clusters what slipped through."""
from __future__ import annotations

import pytest


def _policy():
    import policy
    return policy


NOTE_A = ("---\ntitle: Introhive rollout status\nmemory_type: project_state\n"
          "project: introhive\n---\n"
          "Survivorship rollout is in phase two for canonical contacts.")

NOTE_A_DUP = ("---\ntitle: Introhive rollout\nmemory_type: project_state\n"
              "project: introhive\n---\n"
              "Rollout of survivorship reached phase two (canonical contacts).")


def test_near_duplicate_title_refused_with_pointer(scratch_vault):
    policy = _policy()
    policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/project-memory/introhive-rollout.md",
        NOTE_A, agent="test")
    with pytest.raises(policy.DuplicateMemoryError) as exc:
        policy.write_agent_memory_note(
            scratch_vault, "40-agent-memory/project-memory/introhive-rollout-v2.md",
            NOTE_A_DUP, agent="test")
    assert "introhive-rollout.md" in str(exc.value)
    assert "force" in str(exc.value)
    assert not (scratch_vault / "40-agent-memory/project-memory/introhive-rollout-v2.md").exists()


def test_force_overrides_refusal(scratch_vault):
    policy = _policy()
    policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/project-memory/introhive-rollout.md",
        NOTE_A, agent="test")
    out = policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/project-memory/introhive-rollout-v2.md",
        NOTE_A_DUP, agent="test", force=True)
    assert out["review_status"] == "unreviewed"


def test_updating_existing_note_never_refused(scratch_vault):
    policy = _policy()
    rel = "40-agent-memory/project-memory/introhive-rollout.md"
    policy.write_agent_memory_note(scratch_vault, rel, NOTE_A, agent="test")
    out = policy.write_agent_memory_note(
        scratch_vault, rel, NOTE_A + "\nPhase three planned.", agent="test")
    assert out["path"] == rel
    note = policy.read_note(scratch_vault, rel)
    assert "Phase three" in note["body"]


def test_same_filename_in_other_folder_refused(scratch_vault):
    policy = _policy()
    policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/constraints/deploy-window.md",
        "---\ntitle: Deploy window\nmemory_type: constraint\n---\nNo Friday deploys.",
        agent="test")
    with pytest.raises(policy.DuplicateMemoryError) as exc:
        policy.write_agent_memory_note(
            scratch_vault, "40-agent-memory/observations/deploy-window.md",
            "---\ntitle: Completely different words here\nmemory_type: observation\n---\n"
            "Totally unrelated body content about gardening.", agent="test")
    assert "same filename" in str(exc.value)


def test_content_term_overlap_refused(scratch_vault):
    policy = _policy()
    body = ("Kafka partitions replication consumer offsets throughput "
            "compaction retention brokers") * 3
    policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/observations/kafka-notes.md",
        f"---\ntitle: Kafka operations\nmemory_type: observation\n---\n{body}",
        agent="test")
    with pytest.raises(policy.DuplicateMemoryError):
        policy.write_agent_memory_note(
            scratch_vault, "40-agent-memory/observations/streaming-platform.md",
            f"---\ntitle: Streaming platform learnings\nmemory_type: observation\n---\n{body}",
            agent="test")


def test_distinct_topics_pass(scratch_vault):
    policy = _policy()
    policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/observations/kafka-notes.md",
        "---\ntitle: Kafka operations\nmemory_type: observation\n---\n"
        "Partition rebalancing stalls under high consumer churn.", agent="test")
    out = policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/preferences/markdown-style.md",
        "---\ntitle: Markdown style preference\nmemory_type: preference\n---\n"
        "User prefers reference-style links in long documents.", agent="test")
    assert out["path"].endswith("markdown-style.md")


def test_memory_index_files_exempt(scratch_vault):
    policy = _policy()
    # A note legitimately titled like the index must not collide with MEMORY.md.
    out = policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/observations/memory-index-note.md",
        "---\ntitle: Agent memory index observations\nmemory_type: observation\n---\n"
        "The memory index format works well.", agent="test")
    assert out["review_status"] == "unreviewed"


def test_find_duplicate_memory_clusters(scratch_vault):
    import find_duplicate_memory as fdm
    policy = _policy()
    policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/project-memory/introhive-rollout.md",
        NOTE_A, agent="test")
    policy.write_agent_memory_note(
        scratch_vault, "40-agent-memory/project-memory/introhive-rollout-v2.md",
        NOTE_A_DUP, agent="test", force=True)

    report = fdm.find(scratch_vault)
    assert report["clusters"], "expected at least one duplicate cluster"
    target = {
        "40-agent-memory/project-memory/introhive-rollout.md",
        "40-agent-memory/project-memory/introhive-rollout-v2.md",
    }
    matching = [c for c in report["clusters"] if set(c["paths"]) >= target]
    assert matching, report["clusters"]
    assert matching[0]["reasons"]
