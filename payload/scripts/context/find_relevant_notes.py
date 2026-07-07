#!/usr/bin/env python3
"""find_relevant_notes — staged retrieval across collections (spec §10.3).

Usage: find_relevant_notes.py --topic TOPIC [--project P] [--max-results N] [--vault DIR]

Searches collections in priority order (decisions -> curated -> context-packs
-> core-memory -> projects -> sources-converted), deduplicated by path.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "lib"))
sys.path.insert(0, str(_HERE.parent / "search"))
import sb_search  # noqa: E402
import sb_vault  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--topic", required=True)
    ap.add_argument("--project")
    ap.add_argument("--max-results", type=int, default=10)
    ap.add_argument("--vault")
    args = ap.parse_args()
    vault = sb_vault.vault_root(args.vault)
    results = sb_search.staged_search(vault, args.topic, args.project,
                                      max(1, min(args.max_results, 50)))
    sb_vault.log_access(vault, "find_relevant_notes", topic=args.topic,
                        results=len(results))
    print(json.dumps({"topic": args.topic, "results": results}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
