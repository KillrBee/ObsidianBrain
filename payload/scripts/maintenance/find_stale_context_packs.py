#!/usr/bin/env python3
"""find_stale_context_packs — packs whose source notes changed after the pack
was generated, or whose source notes are gone (spec §10.5).

Usage: find_stale_context_packs.py [--vault DIR]
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_frontmatter  # noqa: E402
import sb_vault  # noqa: E402


def find(vault: Path) -> dict:
    stale = []
    for area in ("active", "drafts"):
        for pack in sorted((vault / "50-context-packs" / area).glob("*.md")):
            meta, _ = sb_frontmatter.read_note(pack)
            meta = meta or {}
            pack_mtime = datetime.fromtimestamp(pack.stat().st_mtime, tz=timezone.utc)
            reasons = []
            for rel in meta.get("source_notes") or []:
                src = vault / rel
                if not src.is_file():
                    reasons.append(f"source missing: {rel}")
                    continue
                src_mtime = datetime.fromtimestamp(src.stat().st_mtime, tz=timezone.utc)
                if src_mtime > pack_mtime:
                    reasons.append(f"source updated after pack: {rel}")
            if reasons:
                stale.append({"path": str(pack.relative_to(vault)),
                              "reasons": reasons})
    return {"total": len(stale), "results": stale}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vault")
    args = ap.parse_args()
    print(json.dumps(find(sb_vault.vault_root(args.vault)), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
