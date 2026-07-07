"""convert_one: frontmatter injection, routing, manifest, failure paths."""
from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "tests" / "fixtures"

pytestmark = pytest.mark.skipif(
    not (REPO_ROOT / ".venv" / "bin" / "markitdown").exists()
    and not shutil.which("markitdown"),
    reason="markitdown not available",
)


def _convert(vault: Path, source: Path, *args: str) -> subprocess.CompletedProcess:
    env = {**os.environ, "SB_VAULT_DIR": str(vault)}
    mk = REPO_ROOT / ".venv" / "bin" / "markitdown"
    if mk.exists():
        env["SB_MARKITDOWN_BIN"] = str(mk)
    return subprocess.run(
        [sys.executable, str(vault / "70-scripts/convert/convert_one.py"),
         "--vault", str(vault), "--source", str(source), *args],
        capture_output=True, text=True, env=env,
    )


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_html_conversion_end_to_end(scratch_vault):
    import sb_frontmatter
    import sb_manifest
    src = scratch_vault / "10-originals/html/fixture.html"
    shutil.copy(FIXTURES / "sample.html", src)
    before = _sha(src)

    proc = _convert(scratch_vault, src)
    assert proc.returncode == 0, proc.stderr

    out = scratch_vault / "20-converted/html-md/fixture.md"
    assert out.is_file()
    meta, body = sb_frontmatter.read_note(out)
    assert meta["doc_type"] == "source_conversion"
    assert meta["source_file"] == "10-originals/html/fixture.html"
    assert meta["source_checksum"] == f"sha256:{before}"
    assert meta["source_format"] == "html"
    assert meta["review_status"] == "unreviewed"
    assert "Sample HTML for SecondBrain" in body

    entry = sb_manifest.find_by_checksum(sb_manifest.load(scratch_vault), f"sha256:{before}")
    assert entry and entry["conversion_status"] == "success"
    assert entry["converted_path"] == "20-converted/html-md/fixture.md"

    assert _sha(src) == before  # original untouched


def test_skip_then_force(scratch_vault):
    src = scratch_vault / "10-originals/html/fixture.html"
    shutil.copy(FIXTURES / "sample.html", src)
    assert _convert(scratch_vault, src).returncode == 0
    assert _convert(scratch_vault, src).returncode == 3  # dedupe by checksum
    assert _convert(scratch_vault, src, "--force").returncode == 0


def test_corrupt_input_records_failure(scratch_vault):
    import sb_manifest
    src = scratch_vault / "10-originals/pdf/corrupt.pdf"
    shutil.copy(FIXTURES / "corrupt.pdf", src)
    proc = _convert(scratch_vault, src)
    assert proc.returncode == 1
    data = sb_manifest.load(scratch_vault)
    failures = [e for e in data["documents"] if e["conversion_status"] == "failure"]
    assert failures and failures[0]["errors"]
    assert (scratch_vault / "80-logs/errors/errors.jsonl").exists()


def test_name_collision_disambiguates_by_checksum(scratch_vault):
    src1 = scratch_vault / "10-originals/html/report.html"
    shutil.copy(FIXTURES / "sample.html", src1)
    assert _convert(scratch_vault, src1).returncode == 0

    src2 = scratch_vault / "10-originals/other/report.html"  # same name, new content
    src2.write_text("<html><head><title>Different Report</title></head>"
                    "<body><h1>Different Report</h1><p>Other text.</p></body></html>")
    assert _convert(scratch_vault, src2).returncode == 0

    out_dir = scratch_vault / "20-converted/html-md"
    outputs = sorted(p.name for p in out_dir.glob("report*.md"))
    assert len(outputs) == 2
    assert any("--" in name for name in outputs)  # checksum-suffixed variant
