#!/usr/bin/env python3
"""policy — permission boundaries + guarded vault operations (spec §11, §22).

Everything the MCP server exposes goes through this module. It has no MCP
dependency so the write/read discipline is testable and usable standalone:

    policy.py --selftest [--vault DIR]

Boundaries:
    reads  : 20-converted, 30-curated, 40-agent-memory, 50-context-packs,
             MEMORY.md, README.md (+ manifest metadata lookups)
    writes : 40-agent-memory, 50-context-packs — Markdown only, frontmatter
             stamped review_status: unreviewed
    never  : originals content, curated writes, deletes, paths outside vault,
             excluded/credential-looking files
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_frontmatter  # noqa: E402
import sb_manifest  # noqa: E402
import sb_schemas  # noqa: E402
import sb_similarity  # noqa: E402
import sb_vault  # noqa: E402

READ_ALLOW = ("20-converted", "30-curated", "40-agent-memory",
              "50-context-packs", "MEMORY.md", "README.md")
WRITE_ALLOW = ("40-agent-memory", "50-context-packs")
READ_CAP_BYTES = 512 * 1024


class PolicyError(PermissionError):
    """Raised when a request falls outside the allowed boundaries."""


class DuplicateMemoryError(PolicyError):
    """Raised when creating a memory note that near-duplicates an existing
    one. Append/update the existing note, or pass force=True if the topic is
    genuinely distinct."""


def _resolve(vault: Path, rel_path: str) -> Path:
    """Resolve a vault-relative path, rejecting escapes and absolute paths."""
    if not rel_path or rel_path.startswith(("/", "~")):
        raise PolicyError(f"absolute paths are not allowed: {rel_path!r}")
    candidate = (vault / rel_path).resolve()
    vault_resolved = vault.resolve()
    if candidate != vault_resolved and vault_resolved not in candidate.parents:
        raise PolicyError(f"path escapes the vault: {rel_path!r}")
    return candidate


def _check_prefix(vault: Path, target: Path, allowed: tuple, action: str) -> str:
    rel = str(target.resolve().relative_to(vault.resolve()))
    for prefix in allowed:
        if rel == prefix or rel.startswith(prefix + "/"):
            break
    else:
        raise PolicyError(
            f"{action} not permitted for {rel!r} (allowed: {', '.join(allowed)})")
    if sb_vault.is_excluded(Path(rel), sb_vault.load_excludes(vault)):
        raise PolicyError(f"{rel!r} matches an excluded pattern")
    return rel


def check_read(vault: Path, rel_path: str) -> Path:
    target = _resolve(vault, rel_path)
    _check_prefix(vault, target, READ_ALLOW, "read")
    return target


def check_write(vault: Path, rel_path: str) -> Path:
    target = _resolve(vault, rel_path)
    rel = _check_prefix(vault, target, WRITE_ALLOW, "write")
    if not rel.endswith(".md"):
        raise PolicyError("agents may only write Markdown (.md) files")
    return target


# ------------------------------------------------------------- read ops -----
def read_note(vault: Path, rel_path: str) -> dict:
    target = check_read(vault, rel_path)
    if not target.is_file():
        raise FileNotFoundError(f"note not found: {rel_path}")
    text = target.read_text(encoding="utf-8", errors="replace")[:READ_CAP_BYTES]
    meta, body = sb_frontmatter.parse(text)
    sb_vault.log_access(vault, "read_note", path=rel_path)
    return {"path": rel_path, "frontmatter": meta or {}, "body": body}


def read_context_pack(vault: Path, name: str) -> dict:
    if "/" in name or name.startswith("."):
        raise PolicyError("context pack names are bare file names")
    stem = name[:-3] if name.endswith(".md") else name
    for area in ("active", "drafts", "archived"):
        rel = f"50-context-packs/{area}/{stem}.md"
        if (vault / rel).is_file():
            return read_note(vault, rel)
    raise FileNotFoundError(f"context pack not found: {name}")


def read_source_metadata(vault: Path, rel_path: str) -> dict:
    """Manifest + frontmatter metadata for an original or converted file.
    This is the sanctioned way to 'look at' 10-originals (spec §6.1)."""
    manifest = sb_manifest.load(vault)
    entry = (sb_manifest.find_by_source(manifest, rel_path)
             or next((e for e in manifest["documents"]
                      if e.get("converted_path") == rel_path), None))
    if entry is None:
        raise FileNotFoundError(f"no manifest entry for: {rel_path}")
    sb_vault.log_access(vault, "read_source_metadata", path=rel_path)
    return entry


def read_manifest(vault: Path, document_id: str) -> dict:
    manifest = sb_manifest.load(vault)
    for entry in manifest["documents"]:
        if entry.get("document_id") == document_id:
            return entry
    raise FileNotFoundError(f"no manifest entry with document_id: {document_id}")


# ------------------------------------------------------------ write ops -----
def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9-]+", "-", text.lower()).strip("-") or "note"


def _stamp_memory_meta(meta: dict, defaults: dict) -> dict:
    merged = {**defaults, **(meta or {})}
    merged["doc_type"] = "agent_memory"
    merged["review_status"] = "unreviewed"   # agents never self-review
    merged.setdefault("created", sb_vault.now_iso())
    merged["updated"] = sb_vault.now_iso()
    return merged


def find_similar_memory(vault: Path, rel_path: str, meta: dict | None,
                        body: str) -> list[dict]:
    """Existing memory notes that look like duplicates of the candidate.
    Index files (MEMORY.md) are exempt."""
    matches = []
    root = vault / "40-agent-memory"
    for existing in sorted(root.rglob("*.md")):
        ex_rel = str(existing.relative_to(vault))
        if existing.name == "MEMORY.md" or ex_rel == rel_path:
            continue
        ex_meta, ex_body = sb_frontmatter.read_note(existing)
        reason = sb_similarity.similarity(meta, body, rel_path,
                                          ex_meta, ex_body, ex_rel)
        if reason:
            matches.append({"path": ex_rel,
                            "title": (ex_meta or {}).get("title"),
                            "reason": reason})
    return matches


def write_agent_memory_note(vault: Path, rel_path: str, content: str,
                            agent: str | None = None,
                            force: bool = False) -> dict:
    target = check_write(vault, rel_path)
    if not rel_path.startswith("40-agent-memory/"):
        raise PolicyError("memory notes must live under 40-agent-memory/")
    meta, body = sb_frontmatter.parse(content)
    meta = _stamp_memory_meta(meta or {}, {
        "title": Path(rel_path).stem.replace("-", " "),
        "memory_type": "observation",
        "project": None,
        "confidence": "medium",
        "source": None,
        "agent": agent,
        "tags": [],
    })
    # Anti-duplication guard: creating a NEW file that near-duplicates an
    # existing note is refused; updating an existing note is always allowed
    # (that is the behavior we want to encourage).
    if not target.exists() and not force:
        dupes = find_similar_memory(vault, rel_path, meta, body)
        if dupes:
            listing = "; ".join(f"{d['path']} ({d['reason']})" for d in dupes[:3])
            raise DuplicateMemoryError(
                f"suspected duplicate of existing memory: {listing}. "
                f"Update that note (write to its path) or use "
                f"append_observation; pass force=true only if the topic is "
                f"genuinely distinct.")
    errors = sb_schemas.validate(vault, meta)
    if errors:
        raise ValueError(f"frontmatter failed agent_memory schema: {errors}")
    sb_frontmatter.write_note(target, meta, body)
    sb_vault.log_access(vault, "write_agent_memory_note", path=rel_path,
                        agent=agent, forced=bool(force))
    return {"path": rel_path, "review_status": "unreviewed"}


def _append_entity_line(vault: Path, folder: str, entity: str, heading: str,
                        line: str, memory_type: str, agent: str | None,
                        project: str | None) -> dict:
    rel = f"40-agent-memory/{folder}/{_slug(entity)}.md"
    target = check_write(vault, rel)
    if target.is_file():
        meta, body = sb_frontmatter.read_note(target)
        meta = _stamp_memory_meta(meta or {}, {})
        meta.setdefault("title", entity)
        meta.setdefault("memory_type", memory_type)
    else:
        meta = _stamp_memory_meta({}, {
            "title": entity, "memory_type": memory_type, "project": project,
            "confidence": "medium", "source": None, "agent": agent, "tags": [],
        })
        body = f"# {entity}\n"
    if heading not in body:
        body = body.rstrip("\n") + f"\n\n{heading}\n"
    body = body.rstrip("\n") + f"\n{line}\n"
    sb_frontmatter.write_note(target, meta, body)
    return {"path": rel, "review_status": "unreviewed"}


def append_observation(vault: Path, entity: str, observation: str,
                       confidence: str = "medium", source: str | None = None,
                       agent: str | None = None, project: str | None = None) -> dict:
    line = f"- [{sb_vault.now_iso()}] {observation} (confidence: {confidence}" \
           + (f", source: {source}" if source else "") + ")"
    result = _append_entity_line(vault, "observations", entity,
                                 "## Observations", line, "observation",
                                 agent, project)
    sb_vault.log_access(vault, "append_observation", entity=entity, agent=agent)
    return result


def append_relation(vault: Path, source_entity: str, relation: str,
                    target_entity: str, confidence: str = "medium",
                    source: str | None = None, agent: str | None = None,
                    project: str | None = None) -> dict:
    line = (f"- [{sb_vault.now_iso()}] [[{_slug(source_entity)}]] **{relation}** "
            f"[[{_slug(target_entity)}]] (confidence: {confidence}"
            + (f", source: {source}" if source else "") + ")")
    result = _append_entity_line(vault, "relations", source_entity,
                                 "## Relations", line, "relation",
                                 agent, project)
    sb_vault.log_access(vault, "append_relation", entity=source_entity,
                        relation=relation, target=target_entity, agent=agent)
    return result


def mark_memory_for_review(vault: Path, rel_path: str) -> dict:
    target = check_write(vault, rel_path)
    if not target.is_file():
        raise FileNotFoundError(f"note not found: {rel_path}")
    meta, body = sb_frontmatter.read_note(target)
    meta = meta or {}
    tags = list(meta.get("tags") or [])
    if "review-requested" not in tags:
        tags.append("review-requested")
    meta["tags"] = tags
    meta["updated"] = sb_vault.now_iso()
    sb_frontmatter.write_note(target, meta, body)
    return {"path": rel_path, "tags": tags}


def summarize_sources(vault: Path, paths: list[str],
                      target_folder: str = "40-agent-memory/observations",
                      agent: str | None = None) -> dict:
    """Extractive draft summary of converted notes, written as unreviewed
    agent memory (promotion into 30-curated stays human-only, spec §23)."""
    if not target_folder.startswith(WRITE_ALLOW):
        raise PolicyError(f"summaries may only be written under {WRITE_ALLOW}")
    sections = []
    for rel in paths:
        note = read_note(vault, rel)
        lines = [ln for ln in note["body"].splitlines() if ln.strip()]
        headings = [ln for ln in lines if ln.startswith("#")][:5]
        first_para = next((ln for ln in lines if not ln.startswith("#")), "")
        sections.append(f"## {note['frontmatter'].get('title', rel)}\n"
                        f"source: [[{rel}]]\n\n"
                        + "\n".join(headings) + f"\n\n{first_para[:500]}\n")
    name = _slug("summary-" + "-".join(Path(p).stem for p in paths[:2]))[:80]
    rel_out = f"{target_folder.rstrip('/')}/{name}.md"
    body = "# Draft summary (extractive, unreviewed)\n\n" + "\n".join(sections)
    return write_agent_memory_note(vault, rel_out, body, agent=agent)


# ------------------------------------------------------------- selftest -----
def selftest(vault: Path) -> int:
    rel = "40-agent-memory/observations/policy-selftest.md"
    write_agent_memory_note(vault, rel, "Selftest observation body.", agent="selftest")
    note = read_note(vault, rel)
    assert note["frontmatter"]["review_status"] == "unreviewed"
    # Entity name shares no title tokens with the note above, so fresh vaults
    # do not ship a benign cluster in the find_duplicate_memory report.
    append_observation(vault, "installer validation entity", "selftest ran", "high")
    for should_fail, fn in [
        ("write to curated", lambda: check_write(vault, "30-curated/concepts/x.md")),
        ("write to originals", lambda: check_write(vault, "10-originals/pdf/x.md")),
        ("path escape", lambda: check_read(vault, "../outside.md")),
        ("read originals content", lambda: check_read(vault, "10-originals/pdf/a.pdf")),
    ]:
        try:
            fn()
        except PolicyError:
            continue
        print(f"selftest FAILED: {should_fail} was allowed", file=sys.stderr)
        return 1
    print("policy selftest ok")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--selftest" in args:
        cli_vault = None
        if "--vault" in args:
            cli_vault = args[args.index("--vault") + 1]
        sys.exit(selftest(sb_vault.vault_root(cli_vault)))
    print(__doc__)
