"""sb_vault — vault root resolution, collections, excludes, access logging.

Shared by every vault-side Python tool. Stdlib + PyYAML only.
"""
from __future__ import annotations

import fnmatch
import json
import os
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover - environment guard
    raise SystemExit(
        "PyYAML is required. Run the installer (creates 70-scripts/.venv) or "
        "`pip install pyyaml`."
    ) from exc


def vault_root(cli_value: str | None = None) -> Path:
    """--vault flag > SB_VAULT_DIR env > derived from this file's location."""
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    env = os.environ.get("SB_VAULT_DIR")
    if env:
        return Path(env).expanduser().resolve()
    # <vault>/70-scripts/lib/sb_vault.py -> parents[2]
    return Path(__file__).resolve().parents[2]


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def today() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


# ------------------------------------------------------------- collections --
def load_collections(vault: Path) -> dict:
    """Returns {"collections": {name: [globs]}, "search_priority": [names]}."""
    cfg_path = vault / "60-index-config" / "qmd" / "collections.yaml"
    with open(cfg_path) as f:
        raw = yaml.safe_load(f) or {}
    collections = {
        name: list(spec.get("globs", []))
        for name, spec in (raw.get("collections") or {}).items()
    }
    priority = list(raw.get("search_priority") or collections.keys())
    return {"collections": collections, "search_priority": priority}


def collection_files(vault: Path, globs: list[str]) -> list[Path]:
    """Expand collection globs relative to the vault, excluded paths removed."""
    excludes = load_excludes(vault)
    seen: dict[Path, None] = {}
    for pattern in globs:
        for p in sorted(vault.glob(pattern)):
            if p.is_file() and not is_excluded(p.relative_to(vault), excludes):
                seen[p] = None
    return list(seen)


# ---------------------------------------------------------------- excludes --
_HARD_EXCLUDES = [".env", "*.pem", "*.key", "id_rsa", "id_ed25519",
                  "secrets.*", "credentials.*", ".git", "node_modules", ".venv"]


def load_excludes(vault: Path) -> list[str]:
    patterns = list(_HARD_EXCLUDES)
    path = vault / "60-index-config" / "qmd" / "exclude-patterns.txt"
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                patterns.append(line)
    return patterns


def is_excluded(rel_path: Path, patterns: list[str]) -> bool:
    parts = rel_path.parts
    for pattern in patterns:
        if any(fnmatch.fnmatch(part, pattern) for part in parts):
            return True
        if fnmatch.fnmatch(str(rel_path), pattern):
            return True
    return False


# ----------------------------------------------------------------- logging --
def log_jsonl(vault: Path, area: str, record: dict) -> None:
    """Append one JSON line under 80-logs/<area>/. Never raises."""
    try:
        log_dir = vault / "80-logs" / area
        log_dir.mkdir(parents=True, exist_ok=True)
        record = {"ts": now_iso(), **record}
        with open(log_dir / f"{area}.jsonl", "a") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def log_access(vault: Path, tool: str, **fields) -> None:
    log_jsonl(vault, "agent-access", {"tool": tool, **fields})
