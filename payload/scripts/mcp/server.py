#!/usr/bin/env python3
"""second-brain MCP server (spec §10) — scoped lookup, bounded memory writes,
context packs. Deliberately NOT exposed (spec §11): deletes, overwrites of
curated notes or originals, bulk modification, unbounded reads, git commit/push.

Run over stdio via the second-brain-mcp launcher, or:
    server.py --selfcheck     # instantiate and list tools, no serving
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SCRIPTS = _HERE.parent
for sub in ("lib", "search", "context", "maintenance", "mcp"):
    sys.path.insert(0, str(_SCRIPTS / sub))

import build_context_pack as ctx_build  # noqa: E402
import find_duplicate_memory as maint_duplicates  # noqa: E402
import find_stale_context_packs as maint_stale  # noqa: E402
import find_superseded_notes as maint_superseded  # noqa: E402
import find_unreviewed_conversions as maint_unreviewed  # noqa: E402
import policy  # noqa: E402
import refresh_context_pack as ctx_refresh  # noqa: E402
import sb_frontmatter  # noqa: E402
import sb_search  # noqa: E402
import sb_vault  # noqa: E402
import validate_frontmatter as maint_validate  # noqa: E402

from mcp.server.fastmcp import FastMCP  # noqa: E402

VAULT = sb_vault.vault_root()
app = FastMCP(
    "second-brain",
    instructions=(
        "Scoped retrieval over a local second-brain vault — the user's single "
        "durable memory across projects. Staged lookup: search_decisions and "
        "search_curated first, search_sources last; results carry "
        "trust_level/review_status and unreviewed content is a lead, not a "
        "fact. Memory discipline: search before writing "
        "(find_relevant_notes/search_agent_memory); prefer append_observation/"
        "append_relation (one note per entity) over creating files; "
        "write_agent_memory_note refuses near-duplicates — append to the note "
        "it names rather than forcing. Update notes in place when facts "
        "change; store deltas and pointers ([[wikilinks]]), never transcripts "
        "or copies of curated content. Durable cross-project knowledge "
        "belongs here; keep per-project memory files to repo mechanics plus a "
        "pointer. Writes are limited to agent memory and context packs and "
        "stay unreviewed until a human promotes them."
    ),
)

MAX_RESULTS = 20


def _clamp(n: int) -> int:
    return max(1, min(int(n), MAX_RESULTS))


def _post_filter(results: list[dict], key: str, value: str | None) -> list[dict]:
    """Filter search hits on a frontmatter key by reading each note (cheap:
    result sets are already capped)."""
    if not value:
        return results
    kept = []
    for r in results:
        meta, _ = sb_frontmatter.read_note(VAULT / r["path"])
        if str((meta or {}).get(key) or "").lower() == value.lower():
            kept.append(r)
    return kept


# ------------------------------------------------------------ search tools --
@app.tool()
def search_curated(query: str, project: str = "", domain: str = "",
                   status: str = "", max_results: int = 10) -> dict:
    """Search human-reviewed curated notes (trusted knowledge). Start here
    after search_decisions."""
    return sb_search.search(VAULT, query, "curated", project or None,
                            domain or None, status or None, _clamp(max_results))


@app.tool()
def search_decisions(query: str, project: str = "", status: str = "",
                     max_results: int = 10) -> dict:
    """Search decision notes. Accepted decisions outrank everything else in
    this vault — always check here first."""
    return sb_search.search(VAULT, query, "decisions", project or None, None,
                            status or None, _clamp(max_results))


@app.tool()
def search_sources(query: str, project: str = "", source_type: str = "",
                   date_range: str = "", max_results: int = 10) -> dict:
    """Search converted source documents (source-derived, unreviewed — cite as
    evidence, not fact). source_type: pdf|docx|pptx|xlsx|html|email|audio|image.
    date_range: YYYY-MM-DD..YYYY-MM-DD (filters converted_at)."""
    out = sb_search.search(VAULT, query, "sources-converted", project or None,
                           None, None, _clamp(max_results))
    results = _post_filter(out["results"], "source_format", source_type or None)
    if date_range and ".." in date_range:
        start, _, end = date_range.partition("..")
        kept = []
        for r in results:
            meta, _b = sb_frontmatter.read_note(VAULT / r["path"])
            ts = str((meta or {}).get("converted_at") or "")[:10]
            if (not start or ts >= start.strip()) and (not end or ts <= end.strip()):
                kept.append(r)
        results = kept
    out["results"] = results
    return out


@app.tool()
def search_agent_memory(query: str, project: str = "", memory_type: str = "",
                        max_results: int = 10) -> dict:
    """Search machine-written memory (observations, relations, constraints,
    preferences). Unreviewed memory is a lead, not a fact."""
    out = sb_search.search(VAULT, query, "core-memory", project or None, None,
                           None, _clamp(max_results))
    out["results"] = _post_filter(out["results"], "memory_type",
                                  memory_type or None)
    return out


@app.tool()
def search_all_markdown(query: str, max_results: int = 10) -> dict:
    """Bounded search across all collections in priority order. Prefer the
    scoped search tools; this is the fallback, capped at 20 results."""
    return sb_search.search(VAULT, query, "all", max_results=_clamp(max_results))


# -------------------------------------------------------------- read tools --
@app.tool()
def read_note(path: str) -> dict:
    """Read one note (vault-relative path) from converted, curated, agent
    memory, or context packs. Originals are not readable — use
    read_source_metadata for their provenance."""
    return policy.read_note(VAULT, path)


@app.tool()
def read_context_pack(name: str) -> dict:
    """Read a context pack by name from 50-context-packs (active, then
    drafts, then archived)."""
    return policy.read_context_pack(VAULT, name)


@app.tool()
def read_source_metadata(path: str) -> dict:
    """Manifest metadata (checksum, formats, conversion status, review status)
    for an original or converted file path."""
    return policy.read_source_metadata(VAULT, path)


@app.tool()
def read_manifest(document_id: str) -> dict:
    """Conversion-manifest entry by document_id."""
    return policy.read_manifest(VAULT, document_id)


# ----------------------------------------------------------- context tools --
@app.tool()
def build_context_pack(topic: str, project: str = "", max_tokens: int = 6000) -> dict:
    """Build a compact context pack for a topic via staged retrieval. Returns
    the pack path plus its source notes; read it with read_context_pack."""
    return ctx_build.build_pack(VAULT, topic, project or None,
                                max(500, min(int(max_tokens), 32000)))


@app.tool()
def refresh_context_pack(name: str) -> dict:
    """Regenerate an existing context pack from its recorded topic/project.
    The previous version is archived, not overwritten."""
    return ctx_refresh.refresh(VAULT, name)


@app.tool()
def find_relevant_notes(topic: str, project: str = "", max_results: int = 10) -> dict:
    """Staged retrieval across all collections in trust-priority order —
    the cheapest way to scope a task before reading anything."""
    results = sb_search.staged_search(VAULT, topic, project or None,
                                      _clamp(max_results))
    sb_vault.log_access(VAULT, "find_relevant_notes", topic=topic,
                        results=len(results))
    return {"topic": topic, "results": results}


@app.tool()
def summarize_sources(paths: list[str], target_folder: str = "40-agent-memory/observations") -> dict:
    """Write an extractive draft summary of the given converted notes into
    agent memory (unreviewed). Promotion to curated stays with the human."""
    return policy.summarize_sources(VAULT, paths, target_folder, agent="mcp")


# ------------------------------------------------------------ memory tools --
@app.tool()
def write_agent_memory_note(path: str, content: str, force: bool = False) -> dict:
    """Create or update a Markdown note under 40-agent-memory/ — for
    genuinely NEW topics only; prefer append_observation/append_relation for
    facts about known entities, and write to an existing note's path to
    update it. Creating a near-duplicate of an existing note is refused with
    the existing path — append there instead; pass force=true only after
    confirming the topic is distinct. Frontmatter is stamped doc_type:
    agent_memory, review_status: unreviewed."""
    return policy.write_agent_memory_note(VAULT, path, content, agent="mcp",
                                          force=force)


@app.tool()
def append_observation(entity: str, observation: str, confidence: str = "medium",
                       source: str = "") -> dict:
    """PREFERRED memory write: append a timestamped observation to the
    entity's single memory note (40-agent-memory/observations/<entity>.md).
    One note per entity — this is how memory stays deduplicated."""
    return policy.append_observation(VAULT, entity, observation, confidence,
                                     source or None, agent="mcp")


@app.tool()
def append_relation(source_entity: str, relation: str, target_entity: str,
                    confidence: str = "medium", source: str = "") -> dict:
    """PREFERRED for links between entities: append a relation
    (source --relation--> target) to the source entity's memory note
    (40-agent-memory/relations/<entity>.md). One note per entity."""
    return policy.append_relation(VAULT, source_entity, relation, target_entity,
                                  confidence, source or None, agent="mcp")


@app.tool()
def mark_memory_for_review(path: str) -> dict:
    """Tag an agent-memory note review-requested so the human review queue
    picks it up."""
    return policy.mark_memory_for_review(VAULT, path)


# ------------------------------------------------------- maintenance tools --
def _run_script(rel: str, *args: str) -> dict:
    script = VAULT / rel
    proc = subprocess.run([str(script), "--vault", str(VAULT), *args],
                          capture_output=True, timeout=1800)
    return {
        "exit_code": proc.returncode,
        "output": proc.stdout.decode("utf-8", errors="replace")[-4000:],
        "errors": proc.stderr.decode("utf-8", errors="replace")[-2000:],
    }


@app.tool()
def convert_new_documents() -> dict:
    """Run the conversion pipeline: ingest 00-inbox/raw-drops, convert new
    originals to Markdown, update the manifest and indexes."""
    return _run_script("70-scripts/convert/convert_new_documents.sh")


@app.tool()
def reconvert_document(path: str) -> dict:
    """Force reconversion of one original under 10-originals/ (manifest entry
    is updated, originals untouched)."""
    if not path.startswith("10-originals/"):
        raise policy.PolicyError("reconvert_document takes a 10-originals/ path")
    return _run_script("70-scripts/convert/reconvert_document.sh", str(VAULT / path))


@app.tool()
def update_indexes() -> dict:
    """Refresh search indexes (no-op with the built-in backend, real work when
    QMD is installed)."""
    return _run_script("70-scripts/index/update_qmd_indexes.sh")


@app.tool()
def validate_frontmatter(path: str = "") -> dict:
    """Validate frontmatter of managed notes against the schemas in
    60-index-config/schemas/."""
    return maint_validate.scan(VAULT, path or None)


@app.tool()
def find_unreviewed_conversions(max_results: int = 50) -> dict:
    """List conversions still awaiting human review."""
    return maint_unreviewed.find(VAULT, _clamp(max_results) * 5)


@app.tool()
def find_stale_context_packs() -> dict:
    """List context packs whose source notes changed after generation."""
    return maint_stale.find(VAULT)


@app.tool()
def find_superseded_notes() -> dict:
    """List superseded notes that should no longer be cited."""
    return maint_superseded.find(VAULT)


@app.tool()
def find_duplicate_memory() -> dict:
    """Report clusters of suspected duplicate agent-memory notes for human
    consolidation. Report only — never merge or delete notes yourself."""
    return maint_duplicates.find(VAULT)


# ------------------------------------------------------------------- main ---
def selfcheck() -> int:
    import asyncio
    tools = asyncio.run(app.list_tools())
    names = sorted(t.name for t in tools)
    forbidden = {"delete_note", "delete_original", "overwrite_original",
                 "overwrite_curated_note", "bulk_modify_curated",
                 "commit_to_git_without_review", "push_to_remote_without_review",
                 "read_all_files", "search_everything_unbounded"}
    leaked = forbidden & set(names)
    if leaked:
        print(f"selfcheck FAILED: forbidden tools exposed: {leaked}", file=sys.stderr)
        return 1
    print(f"second-brain MCP: {len(names)} tools over vault {VAULT}")
    for n in names:
        print(f"  {n}")
    return 0


if __name__ == "__main__":
    if "--selfcheck" in sys.argv:
        sys.exit(selfcheck())
    app.run()
