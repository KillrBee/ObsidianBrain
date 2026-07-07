#!/usr/bin/env python3
"""refresh_context_pack — rebuild an existing pack from its own frontmatter.

Usage: refresh_context_pack.py --name NAME [--vault DIR]

The previous version is archived by the builder, never overwritten (spec §14).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "lib"))
sys.path.insert(0, str(_HERE))
import build_context_pack  # noqa: E402
import sb_frontmatter  # noqa: E402
import sb_vault  # noqa: E402


def refresh(vault: Path, name: str) -> dict:
    stem = name[:-3] if name.endswith(".md") else name
    for area, activate in (("active", True), ("drafts", False)):
        existing = vault / "50-context-packs" / area / f"{stem}.md"
        if existing.is_file():
            meta, _ = sb_frontmatter.read_note(existing)
            meta = meta or {}
            topic = meta.get("topic") or stem
            return build_context_pack.build_pack(
                vault, topic, meta.get("project"),
                int(meta.get("max_token_target") or 6000),
                name=stem, activate=activate)
    raise FileNotFoundError(f"context pack not found in active/ or drafts/: {name}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", required=True)
    ap.add_argument("--vault")
    args = ap.parse_args()
    result = refresh(sb_vault.vault_root(args.vault), args.name)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
