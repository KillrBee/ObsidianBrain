#!/usr/bin/env python3
"""build_context_pack — assemble a compact, budgeted context pack (spec §14).

Usage:
    build_context_pack.py --topic TOPIC [--project P] [--max-tokens N]
                          [--name NAME] [--activate] [--vault DIR]

Staged retrieval (spec §9.1) feeds ranked notes (spec §9.2 preferences are
baked into the search scoring) into sections, cut off at the token budget.
Existing packs with the same name are archived, never overwritten (spec §14).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "lib"))
sys.path.insert(0, str(_HERE.parent / "search"))
import sb_frontmatter  # noqa: E402
import sb_search  # noqa: E402
import sb_vault  # noqa: E402

OVERHEAD_TOKENS = 400          # frontmatter + section scaffolding
EXCERPT_CHARS = 900


def est_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9-]+", "-", text.lower()).strip("-") or "pack"


def excerpt(body: str, terms: list[str], limit: int = EXCERPT_CHARS) -> str:
    """First prose paragraph containing a term match, else the opening prose;
    headings alone are labels, not content. Capped at `limit` chars."""
    paragraphs = [p.strip() for p in body.split("\n\n") if p.strip()]
    prose = [p for p in paragraphs if not p.lstrip().startswith("#")]
    chosen = None
    for p in prose:
        low = p.lower()
        if any(t in low for t in terms):
            chosen = p
            break
    if chosen is None and prose:
        chosen = prose[0]
    if chosen is None and paragraphs:
        chosen = paragraphs[0]
    text = (chosen or "").strip()
    if len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0] + " …"
    return text


def archive_existing(vault: Path, name: str) -> list[str]:
    """Move same-named packs from active/ and drafts/ into archived/."""
    archived = []
    archive_dir = vault / "50-context-packs" / "archived"
    for area in ("active", "drafts"):
        existing = vault / "50-context-packs" / area / f"{name}.md"
        if existing.is_file():
            archive_dir.mkdir(parents=True, exist_ok=True)
            stamp = sb_vault.now_iso().replace(":", "").replace("-", "")
            dest = archive_dir / f"{name}-{stamp}.md"
            n = 1
            while dest.exists():
                dest = archive_dir / f"{name}-{stamp}-{n}.md"
                n += 1
            existing.rename(dest)
            archived.append(str(dest.relative_to(vault)))
    return archived


def build_pack(vault: Path, topic: str, project: str | None = None,
               max_tokens: int = 6000, name: str | None = None,
               activate: bool = False) -> dict:
    terms = sb_search.tokenize(topic)
    hits = sb_search.staged_search(vault, topic, project=project, max_results=24)
    # A pack must not embed other packs (or itself, on refresh).
    hits = [h for h in hits if h.get("collection") != "context-packs"]

    name = slug(name or (f"{project}-{topic}" if project else topic))
    sections = {"decisions": [], "curated": [], "memory": [], "sources": []}
    section_of = {"decisions": "decisions", "curated": "curated",
                  "projects": "curated", "core-memory": "memory",
                  "sources-converted": "sources"}
    budget = max_tokens - OVERHEAD_TOKENS
    used = 0
    source_notes: list[str] = []
    truncated = 0
    open_questions: list[str] = []

    for hit in hits:
        note_path = vault / hit["path"]
        meta, body = sb_frontmatter.read_note(note_path)
        meta = meta or {}
        if meta.get("superseded_by") or meta.get("status") in ("deprecated", "archived", "rejected"):
            continue
        if meta.get("status") == "proposed":
            open_questions.append(
                f"- [[{hit['path']}]] is still `proposed` — confirm before relying on it.")
        block_body = excerpt(body, terms)
        trust = meta.get("trust_level") or "unknown"
        review = meta.get("review_status") or "unknown"
        block = (f"### {hit['title']}\n"
                 f"`{hit['path']}` — trust: {trust}, review: {review}\n\n"
                 f"{block_body}\n")
        cost = est_tokens(block)
        if used + cost > budget:
            truncated += 1
            continue
        used += cost
        source_notes.append(hit["path"])
        sections[section_of.get(hit.get("collection", ""), "curated")].append(block)

    if truncated:
        open_questions.append(
            f"- {truncated} relevant note(s) were dropped to fit the "
            f"{max_tokens}-token budget; rebuild with --max-tokens to include them.")
    if not any(sections.values()):
        open_questions.append(f"- No notes matched `{topic}` — the vault may not cover this topic yet.")

    title = f"{topic} Context Pack" if not project else f"{project}: {topic} Context Pack"
    meta = {
        "title": title.strip(),
        "doc_type": "context_pack",
        "created": sb_vault.today(),
        "updated": sb_vault.today(),
        "project": project,
        "topic": topic,
        "max_token_target": max_tokens,
        "source_notes": source_notes,
        "review_status": "generated",
        "tags": ["context-pack"],
    }
    body = "\n".join(filter(None, [
        f"# Context Pack: {title.strip()}",
        "",
        "## Purpose",
        "",
        f"Minimum working context for agents working on **{topic}**"
        + (f" in project **{project}**." if project else "."),
        "Prefer the decisions section; source evidence is unreviewed conversion output.",
        "",
        "## Current Decisions", "",
        "\n".join(sections["decisions"]) or "_No accepted decisions found for this topic._",
        "",
        "## Key Concepts", "",
        "\n".join(sections["curated"]) or "_No curated notes found for this topic._",
        "",
        "## Agent Memory (unreviewed)", "",
        "\n".join(sections["memory"]) or "_No agent memory for this topic._",
        "",
        "## Relevant Source Evidence (source-derived, unreviewed)", "",
        "\n".join(sections["sources"]) or "_No converted sources matched._",
        "",
        "## Open Questions", "",
        "\n".join(open_questions) or "_None recorded._",
    ]))

    archived = archive_existing(vault, name)
    area = "active" if activate else "drafts"
    rel_out = f"50-context-packs/{area}/{name}.md"
    sb_frontmatter.write_note(vault / rel_out, meta, body)
    sb_vault.log_access(vault, "build_context_pack", topic=topic,
                        project=project, path=rel_out, sources=len(source_notes))
    return {
        "path": rel_out, "name": name, "token_estimate": used + OVERHEAD_TOKENS,
        "max_token_target": max_tokens, "source_notes": source_notes,
        "archived_previous": archived,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--topic", required=True)
    ap.add_argument("--project")
    ap.add_argument("--max-tokens", type=int, default=6000)
    ap.add_argument("--name")
    ap.add_argument("--activate", action="store_true",
                    help="write to 50-context-packs/active instead of drafts")
    ap.add_argument("--vault")
    args = ap.parse_args()
    vault = sb_vault.vault_root(args.vault)
    result = build_pack(vault, args.topic, args.project, args.max_tokens,
                        args.name, args.activate)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
