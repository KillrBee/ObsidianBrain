"""pytest fixtures: a real installed vault in a temp dir, importable modules."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "tests" / "fixtures"


def _install(vault: Path, home: Path) -> subprocess.CompletedProcess:
    env = {
        **os.environ,
        "HOME": str(home),
        "SB_SKIP_BREW": "1",
        "SB_SKIP_TOOLS": "1",
        "SB_SKIP_OBSIDIAN": "1",
        "SB_PYTHON": sys.executable,
    }
    return subprocess.run(
        [str(REPO_ROOT / "install.sh"), "--mode", "default",
         "--vault-dir", str(vault), "--skip-obsidian", "--claude-scope", "project"],
        capture_output=True, text=True, env=env,
    )


@pytest.fixture(scope="session")
def vault(tmp_path_factory) -> Path:
    root = tmp_path_factory.mktemp("sb")
    vault = root / "vault"
    home = root / "home"
    home.mkdir()
    proc = _install(vault, home)
    assert proc.returncode == 0, f"install failed:\n{proc.stdout}\n{proc.stderr}"
    _import_vault_modules(vault)
    os.environ["SB_VAULT_DIR"] = str(vault)
    return vault


def _import_vault_modules(vault: Path) -> None:
    for sub in ("lib", "search", "context", "maintenance", "mcp"):
        p = str(vault / "70-scripts" / sub)
        if p not in sys.path:
            sys.path.insert(0, p)


@pytest.fixture()
def scratch_vault(vault: Path) -> Path:
    """Function-scoped disposable copy of the installed vault for write tests."""
    dest = Path(tempfile.mkdtemp(prefix="sbscratch")) / "vault"
    shutil.copytree(vault, dest, symlinks=True)
    yield dest
    shutil.rmtree(dest.parent, ignore_errors=True)
