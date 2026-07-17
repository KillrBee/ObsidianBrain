#!/usr/bin/env python3
"""sb_memory — agent-memory writes through the policy layer, for
environments where the MCP server is unavailable (script mode). Same
dedup guard, frontmatter stamping, and access logging as the MCP tools.

Subcommands:
    note <rel_path> [content|-]  [--force]      create/update a memory note
    observe <entity> <observation> [--confidence C] [--source S] [--project P]
    relate <source_entity> <relation> <target_entity> [--confidence C] [--source S]
    review <rel_path>                            tag a note review-requested

Exit codes: 0 ok (JSON on stdout), 2 policy violation,
3 duplicate suspected (stderr names the existing note; append there or --force).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "lib"))
sys.path.insert(0, str(_HERE.parent / "mcp"))
import policy  # noqa: E402
import sb_vault  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vault")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("note", help="create or update a memory note")
    p.add_argument("path", help="vault-relative path under 40-agent-memory/")
    p.add_argument("content", nargs="?",
                   help="note content ('-' or omitted reads stdin)")
    p.add_argument("--force", action="store_true",
                   help="write even if a near-duplicate exists")

    p = sub.add_parser("observe", help="append an observation to an entity note")
    p.add_argument("entity")
    p.add_argument("observation")
    p.add_argument("--confidence", default="medium", choices=["low", "medium", "high"])
    p.add_argument("--source")
    p.add_argument("--project")

    p = sub.add_parser("relate", help="append a relation between entities")
    p.add_argument("source_entity")
    p.add_argument("relation")
    p.add_argument("target_entity")
    p.add_argument("--confidence", default="medium", choices=["low", "medium", "high"])
    p.add_argument("--source")

    p = sub.add_parser("review", help="tag a memory note review-requested")
    p.add_argument("path")

    p = sub.add_parser("summarize",
                       help="write an extractive draft summary of vault notes into agent memory")
    p.add_argument("paths", nargs="+",
                   help="vault-relative note paths (converted or curated)")
    p.add_argument("--target-folder", default="40-agent-memory/observations")

    args = ap.parse_args()
    vault = sb_vault.vault_root(args.vault)

    try:
        if args.cmd == "note":
            content = args.content
            if content in (None, "-"):
                content = sys.stdin.read()
            out = policy.write_agent_memory_note(
                vault, args.path, content, agent="cli", force=args.force)
        elif args.cmd == "observe":
            out = policy.append_observation(
                vault, args.entity, args.observation, args.confidence,
                args.source, agent="cli", project=args.project)
        elif args.cmd == "relate":
            out = policy.append_relation(
                vault, args.source_entity, args.relation, args.target_entity,
                args.confidence, args.source, agent="cli")
        elif args.cmd == "summarize":
            out = policy.summarize_sources(vault, args.paths,
                                           args.target_folder, agent="cli")
        else:
            out = policy.mark_memory_for_review(vault, args.path)
    except policy.DuplicateMemoryError as exc:
        print(f"duplicate: {exc}", file=sys.stderr)
        return 3
    except policy.PolicyError as exc:
        print(f"policy: {exc}", file=sys.stderr)
        return 2
    except (FileNotFoundError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
