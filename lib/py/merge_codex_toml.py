#!/usr/bin/env python3
"""Insert, refresh, or remove the second-brain managed block in a Codex
config.toml. User content outside the markers is preserved byte-for-byte.

Usage:
    merge_codex_toml.py <toml_path> <vault_dir> [--remove]

Exit codes:
    0 ok
    1 unexpected error
    2 existing file is invalid TOML (left untouched)
    3 merge would produce invalid TOML, e.g. the user already defines
      [mcp_servers.second-brain] outside the managed block (left untouched)
"""
import os
import sys
import tomllib

BEGIN = "# >>> second-brain managed block (do not edit inside) >>>"
END = "# <<< second-brain managed block <<<"


def managed_block(vault_dir: str) -> str:
    cmd = os.path.join(vault_dir, "70-scripts", "mcp", "second-brain-mcp")
    return (
        f"{BEGIN}\n"
        f"[mcp_servers.second-brain]\n"
        f'command = "{cmd}"\n'
        f"args = []\n"
        f"\n"
        f"[mcp_servers.basic-memory]\n"
        f'command = "uvx"\n'
        f'args = ["basic-memory", "mcp"]\n'
        f"{END}\n"
    )


def strip_block(text: str) -> str:
    while BEGIN in text:
        start = text.index(BEGIN)
        end = text.find(END, start)
        if end == -1:  # unterminated block: cut to end of file
            text = text[:start]
            break
        text = text[:start] + text[end + len(END):]
    return text.lstrip("\n") if text.strip() else ""


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 1
    path, vault_dir = sys.argv[1], sys.argv[2]
    remove = "--remove" in sys.argv[3:]

    original = ""
    if os.path.exists(path):
        with open(path, "rb") as f:
            raw = f.read()
        try:
            tomllib.loads(raw.decode("utf-8"))
        except (tomllib.TOMLDecodeError, UnicodeDecodeError) as exc:
            print(f"refusing to modify invalid TOML in {path}: {exc}", file=sys.stderr)
            return 2
        original = raw.decode("utf-8")

    body = strip_block(original)
    if remove:
        new_text = body
    else:
        sep = "" if not body else ("\n" if body.endswith("\n") else "\n\n")
        new_text = body + sep + managed_block(vault_dir)

    try:
        tomllib.loads(new_text)
    except tomllib.TOMLDecodeError as exc:
        print(
            f"merge would corrupt {path} (duplicate mcp_servers entry outside "
            f"the managed block?): {exc}",
            file=sys.stderr,
        )
        return 3

    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(new_text)
    os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
