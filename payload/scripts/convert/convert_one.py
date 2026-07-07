#!/usr/bin/env python3
"""convert_one — convert a single original to Markdown (spec §12 steps 3-10).

Usage:
    convert_one.py --source PATH [--vault DIR] [--force]

Exit codes: 0 converted, 3 skipped (already converted), 1 conversion failed.

The original file is never modified. Output goes to 20-converted/<format>-md/
with source_conversion frontmatter; every attempt lands in the conversion
manifest and 80-logs/conversion/.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import sb_frontmatter  # noqa: E402
import sb_manifest  # noqa: E402
import sb_vault  # noqa: E402

# extension -> (source_format, converted subdir)
FORMAT_MAP = {
    ".pdf": ("pdf", "pdf-md"),
    ".docx": ("docx", "docx-md"), ".doc": ("docx", "docx-md"),
    ".pptx": ("pptx", "pptx-md"), ".ppt": ("pptx", "pptx-md"),
    ".xlsx": ("xlsx", "xlsx-md"), ".xls": ("xlsx", "xlsx-md"), ".csv": ("xlsx", "xlsx-md"),
    ".html": ("html", "html-md"), ".htm": ("html", "html-md"),
    ".eml": ("email", "email-md"), ".msg": ("email", "email-md"),
    ".mp3": ("audio", "transcript-md"), ".m4a": ("audio", "transcript-md"),
    ".wav": ("audio", "transcript-md"), ".mp4": ("audio", "transcript-md"),
    ".png": ("image", "image-md"), ".jpg": ("image", "image-md"),
    ".jpeg": ("image", "image-md"), ".gif": ("image", "image-md"),
}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def slugify(stem: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-").lower()
    return slug or "document"


def markitdown_bin() -> str | None:
    env = os.environ.get("SB_MARKITDOWN_BIN")
    if env:
        return env
    return shutil.which("markitdown")


def convert_with_markitdown(source: Path) -> tuple[str | None, str]:
    """Return (markdown, error). markdown is None on failure."""
    binary = markitdown_bin()
    if not binary:
        return None, "markitdown binary not found (install with: uv tool install 'markitdown[pdf,docx,pptx,xlsx]')"
    try:
        proc = subprocess.run(
            [binary, str(source)],
            capture_output=True, timeout=600,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return None, f"markitdown execution failed: {exc}"
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", errors="replace").strip()
        return None, f"markitdown exited {proc.returncode}: {stderr[-800:]}"
    return proc.stdout.decode("utf-8", errors="replace"), ""


def title_from(markdown: str, fallback: str) -> str:
    for line in markdown.splitlines():
        m = re.match(r"^#{1,3}\s+(.+)", line.strip())
        if m:
            return m.group(1).strip()
    return fallback


def output_path(vault: Path, subdir: str, source: Path, checksum: str) -> Path:
    out_dir = vault / "20-converted" / subdir
    candidate = out_dir / f"{slugify(source.stem)}.md"
    if candidate.exists():
        meta, _ = sb_frontmatter.read_note(candidate)
        if meta and meta.get("source_checksum") not in (None, checksum):
            # Same name, different document: disambiguate with checksum prefix.
            short = checksum.split(":", 1)[1][:8]
            candidate = out_dir / f"{slugify(source.stem)}--{short}.md"
    return candidate


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True)
    ap.add_argument("--vault")
    ap.add_argument("--force", action="store_true",
                    help="reconvert even if the manifest already has this checksum")
    args = ap.parse_args()

    vault = sb_vault.vault_root(args.vault)
    source = Path(args.source).expanduser().resolve()
    if not source.is_file():
        print(f"error: source not found: {source}", file=sys.stderr)
        return 1

    checksum = sha256_of(source)
    pre_bytes = checksum  # originals-untouched invariant, checked at the end
    fmt, subdir = FORMAT_MAP.get(source.suffix.lower(), ("other", "other-md"))
    try:
        source_rel = str(source.relative_to(vault))
    except ValueError:
        source_rel = str(source)

    manifest = sb_manifest.load(vault)
    prior = sb_manifest.find_by_checksum(manifest, checksum)
    if prior and prior.get("conversion_status") == "success" and not args.force:
        converted = vault / prior.get("converted_path", "")
        if converted.is_file():
            print(f"skip: already converted -> {prior['converted_path']}")
            return 3

    markdown, error = convert_with_markitdown(source)
    now = sb_vault.now_iso()
    entry = {
        "document_id": checksum.split(":", 1)[1][:16],
        "source_path": source_rel,
        "source_checksum": checksum,
        "source_format": fmt,
        "converted_path": "",
        "converted_at": now,
        "converter": "markitdown",
        "conversion_status": "success" if markdown is not None else "failure",
        "errors": [] if markdown is not None else [error],
        "warnings": [],
        "review_status": "unreviewed",
    }

    if markdown is None:
        sb_manifest.upsert(manifest, entry)
        sb_manifest.save(vault, manifest)
        sb_vault.log_jsonl(vault, "conversion", {"source": source_rel, "status": "failure", "error": error})
        sb_vault.log_jsonl(vault, "errors", {"tool": "convert_one", "source": source_rel, "error": error})
        print(f"error: {error}", file=sys.stderr)
        return 1

    dest = output_path(vault, subdir, source, checksum)
    mtime = datetime.fromtimestamp(source.stat().st_mtime, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    meta = {
        "title": title_from(markdown, source.stem),
        "doc_type": "source_conversion",
        "source_file": source_rel,
        "source_format": fmt,
        "source_checksum": checksum,
        "converted_by": "markitdown",
        "converted_at": now,
        "source_modified_at": mtime,
        "project": None,
        "domain": [],
        "status": "converted",
        "trust_level": "source-derived",
        "review_status": "unreviewed",
        "effective_from": None,
        "effective_to": None,
        "contains_tables": bool(re.search(r"^\s*\|.+\|\s*$", markdown, re.M)),
        "contains_images": "![" in markdown,
        "contains_comments": "unknown",
        "contains_ocr": False,
        "summary_file": None,
        "tags": [],
    }
    sb_frontmatter.write_note(dest, meta, markdown)

    entry["converted_path"] = str(dest.relative_to(vault))
    sb_manifest.upsert(manifest, entry)
    sb_manifest.save(vault, manifest)
    sb_vault.log_jsonl(vault, "conversion", {
        "source": source_rel, "status": "success",
        "converted_path": entry["converted_path"], "checksum": checksum,
    })

    if sha256_of(source) != pre_bytes:  # pragma: no cover - hard invariant
        print("FATAL: original file changed during conversion!", file=sys.stderr)
        return 1

    print(f"converted: {source_rel} -> {entry['converted_path']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
