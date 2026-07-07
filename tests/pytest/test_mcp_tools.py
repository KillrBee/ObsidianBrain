"""MCP server: tool surface matches spec §10, forbidden ops absent (spec §11),
tools work end-to-end in process."""
from __future__ import annotations

import asyncio
import importlib
import os

import pytest

mcp = pytest.importorskip("mcp")

SPEC_TOOLS = {
    # §10.1 search
    "search_curated", "search_decisions", "search_sources",
    "search_agent_memory", "search_all_markdown",
    # §10.2 read
    "read_note", "read_context_pack", "read_source_metadata", "read_manifest",
    # §10.3 context
    "build_context_pack", "refresh_context_pack", "summarize_sources",
    "find_relevant_notes",
    # §10.4 memory
    "write_agent_memory_note", "append_observation", "append_relation",
    "mark_memory_for_review",
    # §10.5 maintenance
    "convert_new_documents", "reconvert_document", "update_indexes",
    "validate_frontmatter", "find_unreviewed_conversions",
    "find_stale_context_packs", "find_superseded_notes",
}

FORBIDDEN = {
    "read_all_files", "search_everything_unbounded", "delete_note",
    "delete_original", "overwrite_original", "overwrite_curated_note",
    "bulk_modify_curated", "bulk_reconvert_without_manifest",
    "commit_to_git_without_review", "push_to_remote_without_review",
}


@pytest.fixture()
def server(scratch_vault):
    os.environ["SB_VAULT_DIR"] = str(scratch_vault)
    import server as srv
    importlib.reload(srv)
    yield srv
    os.environ.pop("SB_VAULT_DIR", None)


def test_tool_surface_matches_spec(server):
    tools = asyncio.run(server.app.list_tools())
    names = {t.name for t in tools}
    assert SPEC_TOOLS <= names, f"missing: {SPEC_TOOLS - names}"
    assert not (FORBIDDEN & names), f"forbidden exposed: {FORBIDDEN & names}"


def test_every_tool_has_a_description(server):
    for tool in asyncio.run(server.app.list_tools()):
        assert tool.description and len(tool.description) > 20, tool.name


def test_search_and_read_flow(server):
    out = server.search_decisions("second brain stack")
    assert out["results"], "seeded decision should be found"
    top = out["results"][0]
    note = server.read_note(top["path"])
    assert note["frontmatter"]["doc_type"] == "decision"


def test_memory_write_and_search_flow(server):
    server.write_agent_memory_note(
        "40-agent-memory/project-memory/introhive-state.md",
        "---\ntitle: Introhive state\nmemory_type: project_state\n---\n"
        "Survivorship rollout is in phase two.")
    out = server.search_agent_memory("survivorship rollout")
    assert any("introhive-state" in r["path"] for r in out["results"])
    # memory_type post-filter works
    filtered = server.search_agent_memory("survivorship rollout", memory_type="project_state")
    assert filtered["results"]
    none = server.search_agent_memory("survivorship rollout", memory_type="lesson")
    assert not none["results"]


def test_context_pack_flow(server, scratch_vault):
    result = server.build_context_pack("second brain stack", max_tokens=3000)
    pack = server.read_context_pack(result["name"])
    assert pack["frontmatter"]["doc_type"] == "context_pack"
    assert pack["frontmatter"]["review_status"] == "generated"


def test_curated_write_rejected_through_server(server):
    import policy
    with pytest.raises(policy.PolicyError):
        server.write_agent_memory_note("30-curated/concepts/hack.md", "nope")


def test_reconvert_rejects_non_original_paths(server):
    import policy
    with pytest.raises(policy.PolicyError):
        server.reconvert_document("30-curated/concepts/second-brain-overview.md")


def test_selfcheck_passes(server):
    assert server.selfcheck() == 0
