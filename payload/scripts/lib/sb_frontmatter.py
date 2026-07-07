"""sb_frontmatter — parse and emit YAML frontmatter on Markdown notes."""
from __future__ import annotations

from pathlib import Path

import yaml

DELIM = "---"


def split(text: str) -> tuple[str | None, str]:
    """Return (frontmatter_text, body). frontmatter_text is None if absent."""
    if not text.startswith(DELIM + "\n") and text.strip() != DELIM:
        return None, text
    lines = text.split("\n")
    for i in range(1, len(lines)):
        if lines[i].strip() == DELIM:
            return "\n".join(lines[1:i]), "\n".join(lines[i + 1:])
    return None, text


def parse(text: str) -> tuple[dict | None, str]:
    """Return (metadata dict | None, body). Malformed YAML -> (None, full text)."""
    fm, body = split(text)
    if fm is None:
        return None, body
    try:
        meta = yaml.safe_load(fm)
    except yaml.YAMLError:
        return None, text
    if not isinstance(meta, dict):
        return None, text
    return meta, body


def dump(meta: dict) -> str:
    return yaml.safe_dump(meta, sort_keys=False, allow_unicode=True,
                          default_flow_style=False).rstrip("\n")


def compose(meta: dict, body: str) -> str:
    return f"{DELIM}\n{dump(meta)}\n{DELIM}\n\n{body.lstrip(chr(10))}"


def read_note(path: Path) -> tuple[dict | None, str]:
    return parse(path.read_text(encoding="utf-8", errors="replace"))


def write_note(path: Path, meta: dict, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(compose(meta, body), encoding="utf-8")
    tmp.replace(path)
