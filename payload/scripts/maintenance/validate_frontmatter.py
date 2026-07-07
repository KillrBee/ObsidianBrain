#!/usr/bin/env python3
"""validate_frontmatter — check every note against its doc_type schema.

Usage: validate_frontmatter.py [--vault DIR] [--path REL_SUBPATH]

Exit 0 when everything under the managed folders validates, 1 otherwise.
Notes without frontmatter in curated folders are reported; plain README /
MEMORY index files are exempt.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_frontmatter  # noqa: E402
import sb_schemas  # noqa: E402
import sb_vault  # noqa: E402

MANAGED = ("20-converted", "30-curated", "40-agent-memory", "50-context-packs")
EXEMPT_NAMES = {"MEMORY.md", "README.md", ".gitkeep"}


def scan(vault: Path, subpath: str | None = None) -> dict:
    roots = [vault / subpath] if subpath else [vault / m for m in MANAGED]
    excludes = sb_vault.load_excludes(vault)
    checked = 0
    problems = []
    for root in roots:
        if not root.exists():
            continue
        for p in sorted(root.rglob("*.md")):
            if p.name in EXEMPT_NAMES:
                continue
            if sb_vault.is_excluded(p.relative_to(vault), excludes):
                continue
            checked += 1
            meta, _ = sb_frontmatter.read_note(p)
            rel = str(p.relative_to(vault))
            if meta is None:
                problems.append({"path": rel, "errors": ["missing or malformed frontmatter"]})
                continue
            errors = sb_schemas.validate(vault, meta)
            if errors:
                problems.append({"path": rel, "errors": errors})
    return {"checked": checked, "invalid": len(problems), "problems": problems}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault")
    ap.add_argument("--path")
    args = ap.parse_args()
    result = scan(sb_vault.vault_root(args.vault), args.path)
    print(json.dumps(result, indent=2))
    return 0 if result["invalid"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
