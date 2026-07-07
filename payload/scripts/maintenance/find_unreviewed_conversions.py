#!/usr/bin/env python3
"""find_unreviewed_conversions — conversions awaiting human review (spec §23).

Usage: find_unreviewed_conversions.py [--vault DIR] [--max-results N]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_manifest  # noqa: E402
import sb_vault  # noqa: E402


def find(vault: Path, max_results: int = 100) -> dict:
    manifest = sb_manifest.load(vault)
    unreviewed = [
        {"document_id": e.get("document_id"),
         "source_path": e.get("source_path"),
         "converted_path": e.get("converted_path"),
         "converted_at": e.get("converted_at"),
         "conversion_status": e.get("conversion_status")}
        for e in manifest["documents"]
        if e.get("review_status") == "unreviewed"
    ]
    unreviewed.sort(key=lambda e: e.get("converted_at") or "")
    return {"total": len(unreviewed), "results": unreviewed[:max_results]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault")
    ap.add_argument("--max-results", type=int, default=100)
    args = ap.parse_args()
    print(json.dumps(find(sb_vault.vault_root(args.vault), args.max_results), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
