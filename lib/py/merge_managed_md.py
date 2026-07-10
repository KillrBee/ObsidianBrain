#!/usr/bin/env python3
"""Insert, refresh, or remove the second-brain managed block in a Markdown
instruction file (~/.claude/CLAUDE.md, ~/.codex/AGENTS.md). User content
outside the markers is preserved byte-for-byte.

Usage:
    merge_managed_md.py <md_path> <content_file> [--remove]

<content_file> holds the inner block content (markers added here).
Exit codes: 0 ok, 1 unexpected error.
"""
import os
import sys

BEGIN = "<!-- >>> second-brain managed block (do not edit inside) >>> -->"
END = "<!-- <<< second-brain managed block <<< -->"


def strip_block(text: str) -> str:
    while BEGIN in text:
        start = text.index(BEGIN)
        end = text.find(END, start)
        if end == -1:
            text = text[:start]
            break
        text = text[:start] + text[end + len(END):]
    return text.strip("\n") + "\n" if text.strip() else ""


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 1
    path, content_file = sys.argv[1], sys.argv[2]
    remove = "--remove" in sys.argv[3:]

    original = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            original = f.read()

    body = strip_block(original)
    if remove:
        new_text = body
        if not new_text and os.path.exists(path):
            # File held only our block: leave an empty file rather than
            # deleting something the user may reference.
            new_text = ""
    else:
        with open(content_file, encoding="utf-8") as f:
            inner = f.read().strip("\n")
        sep = "" if not body else "\n"
        new_text = body + sep + BEGIN + "\n" + inner + "\n" + END + "\n"

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(new_text)
    os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
