#!/usr/bin/env python3
"""checksum_inventory — duplicate detection across 10-originals (spec §6.1).

Usage: checksum_inventory.py [--vault DIR]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_vault  # noqa: E402


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def inventory(vault: Path) -> dict:
    by_sum: dict[str, list[str]] = defaultdict(list)
    root = vault / "10-originals"
    count = 0
    for p in sorted(root.rglob("*")):
        if p.is_file() and p.name not in (".gitkeep", ".DS_Store"):
            count += 1
            by_sum[sha256_of(p)].append(str(p.relative_to(vault)))
    duplicates = [{"checksum": k, "paths": v}
                  for k, v in by_sum.items() if len(v) > 1]
    return {"originals": count, "unique": len(by_sum), "duplicates": duplicates}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault")
    args = ap.parse_args()
    print(json.dumps(inventory(sb_vault.vault_root(args.vault)), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
