"""sb_manifest — the conversion manifest (spec §12), atomic JSON updates."""
from __future__ import annotations

import json
import os
from pathlib import Path


def manifest_path(vault: Path) -> Path:
    return vault / "60-index-config" / "manifests" / "conversion-manifest.json"


def load(vault: Path) -> dict:
    path = manifest_path(vault)
    try:
        with open(path) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}
    data.setdefault("documents", [])
    return data


def save(vault: Path, data: dict) -> None:
    path = manifest_path(vault)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = str(path) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def find_by_checksum(data: dict, checksum: str) -> dict | None:
    for entry in data["documents"]:
        if entry.get("source_checksum") == checksum:
            return entry
    return None


def find_by_source(data: dict, source_path: str) -> dict | None:
    for entry in data["documents"]:
        if entry.get("source_path") == source_path:
            return entry
    return None


def upsert(data: dict, entry: dict) -> None:
    """Replace by document_id, else append."""
    for i, existing in enumerate(data["documents"]):
        if existing.get("document_id") == entry.get("document_id"):
            data["documents"][i] = entry
            return
    data["documents"].append(entry)
