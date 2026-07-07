#!/usr/bin/env python3
"""find_superseded_notes — notes with superseded_by set or superseded status,
so agents (and humans) stop citing them (spec §9.2, §10.5).

Usage: find_superseded_notes.py [--vault DIR]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_frontmatter  # noqa: E402
import sb_vault  # noqa: E402

SCAN_ROOTS = ("20-converted", "30-curated", "40-agent-memory")


def find(vault: Path) -> dict:
    hits = []
    for root in SCAN_ROOTS:
        base = vault / root
        if not base.exists():
            continue
        for p in sorted(base.rglob("*.md")):
            meta, _ = sb_frontmatter.read_note(p)
            meta = meta or {}
            if meta.get("superseded_by") or meta.get("status") == "superseded":
                hits.append({
                    "path": str(p.relative_to(vault)),
                    "title": meta.get("title"),
                    "status": meta.get("status"),
                    "superseded_by": meta.get("superseded_by"),
                })
    return {"total": len(hits), "results": hits}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault")
    args = ap.parse_args()
    print(json.dumps(find(sb_vault.vault_root(args.vault)), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
