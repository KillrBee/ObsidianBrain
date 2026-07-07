"""Context packs: budget respected, archives instead of overwrites, staleness."""
from __future__ import annotations

from pathlib import Path


def _seed_notes(vault: Path, count: int = 8) -> None:
    import sb_frontmatter
    for i in range(count):
        meta = {
            "title": f"Survivorship Concept {i}",
            "doc_type": "curated_synthesis",
            "created": "2026-07-01",
            "updated": "2026-07-01",
            "project": "introhive",
            "domain": ["identity"],
            "status": "active",
            "trust_level": "human-reviewed",
            "review_status": "reviewed",
            "source_files": [],
            "confidence": "high",
            "supersedes": [],
            "superseded_by": None,
            "tags": ["identity-resolution"],
        }
        body = f"# Survivorship Concept {i}\n\n" + \
            ("Survivorship and identity resolution detail sentence. " * 60)
        sb_frontmatter.write_note(
            vault / "30-curated" / "concepts" / f"survivorship-{i}.md", meta, body)


def test_pack_respects_token_budget(scratch_vault):
    import build_context_pack as bcp
    _seed_notes(scratch_vault)
    result = bcp.build_pack(scratch_vault, "survivorship identity resolution",
                            project="introhive", max_tokens=1500)
    assert result["token_estimate"] <= 1500
    pack = scratch_vault / result["path"]
    assert pack.is_file()
    # Real token check on the artifact itself: chars/4 approximation.
    assert len(pack.read_text()) / 4 <= 1500 * 1.25
    assert result["source_notes"], "expected at least one note to fit"


def test_pack_frontmatter_and_sections(scratch_vault):
    import build_context_pack as bcp
    import sb_frontmatter
    _seed_notes(scratch_vault, 3)
    result = bcp.build_pack(scratch_vault, "survivorship", project="introhive",
                            max_tokens=6000)
    meta, body = sb_frontmatter.read_note(scratch_vault / result["path"])
    assert meta["doc_type"] == "context_pack"
    assert meta["review_status"] == "generated"
    assert meta["source_notes"] == result["source_notes"]
    for heading in ("## Purpose", "## Current Decisions", "## Key Concepts",
                    "## Relevant Source Evidence", "## Open Questions"):
        assert heading in body


def test_refresh_archives_previous_version(scratch_vault):
    import build_context_pack as bcp
    import refresh_context_pack as rcp
    _seed_notes(scratch_vault, 2)
    first = bcp.build_pack(scratch_vault, "survivorship", project="introhive",
                           name="surv-pack")
    assert (scratch_vault / first["path"]).is_file()

    second = rcp.refresh(scratch_vault, "surv-pack")
    assert second["path"] == first["path"]
    assert second["archived_previous"], "previous pack should be archived"
    archived = scratch_vault / second["archived_previous"][0]
    assert archived.is_file()
    assert "archived" in str(archived)


def test_budget_overflow_reported_in_open_questions(scratch_vault):
    import build_context_pack as bcp
    _seed_notes(scratch_vault, 10)
    result = bcp.build_pack(scratch_vault, "survivorship identity", max_tokens=900)
    body = (scratch_vault / result["path"]).read_text()
    assert "token budget" in body


def test_stale_detection_after_source_update(scratch_vault):
    import build_context_pack as bcp
    import find_stale_context_packs as stale
    import time
    _seed_notes(scratch_vault, 2)
    result = bcp.build_pack(scratch_vault, "survivorship", name="stale-check")
    assert stale.find(scratch_vault)["total"] == 0

    time.sleep(0.02)
    src = scratch_vault / result["source_notes"][0]
    src.write_text(src.read_text() + "\nUpdated line.\n")
    report = stale.find(scratch_vault)
    assert report["total"] == 1
    assert report["results"][0]["path"] == result["path"]


def test_staged_search_prefers_decisions(scratch_vault):
    import sb_search
    _seed_notes(scratch_vault, 1)
    hits = sb_search.staged_search(scratch_vault, "second brain stack", max_results=10)
    collections = [h["collection"] for h in hits]
    assert "decisions" in collections
    # The seeded decision must outrank curated hits mentioning the same words.
    first_decision = collections.index("decisions")
    assert first_decision == 0, hits
