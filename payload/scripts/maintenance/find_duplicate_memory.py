#!/usr/bin/env python3
"""find_duplicate_memory — cluster suspected duplicate agent-memory notes
for human consolidation (report only; nothing is merged or deleted).

Usage: find_duplicate_memory.py [--vault DIR]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_frontmatter  # noqa: E402
import sb_similarity  # noqa: E402
import sb_vault  # noqa: E402


def find(vault: Path) -> dict:
    notes = []
    root = vault / "40-agent-memory"
    if root.exists():
        for p in sorted(root.rglob("*.md")):
            if p.name == "MEMORY.md":
                continue
            meta, body = sb_frontmatter.read_note(p)
            notes.append((str(p.relative_to(vault)), meta, body))

    # Union-find over pairwise similarity.
    parent = list(range(len(notes)))

    def find_root(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    reasons: dict[tuple[int, int], str] = {}
    for i in range(len(notes)):
        for j in range(i + 1, len(notes)):
            reason = sb_similarity.similarity(
                notes[i][1], notes[i][2], notes[i][0],
                notes[j][1], notes[j][2], notes[j][0])
            if reason:
                reasons[(i, j)] = reason
                ri, rj = find_root(i), find_root(j)
                if ri != rj:
                    parent[rj] = ri

    clusters: dict[int, list[int]] = {}
    for i in range(len(notes)):
        clusters.setdefault(find_root(i), []).append(i)

    out = []
    for members in clusters.values():
        if len(members) < 2:
            continue
        member_set = set(members)
        out.append({
            "paths": [notes[i][0] for i in members],
            "reasons": sorted({r for (i, j), r in reasons.items()
                               if i in member_set and j in member_set}),
        })
    out.sort(key=lambda c: -len(c["paths"]))
    return {"notes_scanned": len(notes), "clusters": out,
            "hint": "Consolidate manually or ask an agent to merge into one "
                    "note and mark the rest superseded — then review."}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault")
    args = ap.parse_args()
    print(json.dumps(find(sb_vault.vault_root(args.vault)), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
