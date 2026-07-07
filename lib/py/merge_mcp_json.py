#!/usr/bin/env python3
"""Merge (or remove) second-brain MCP server entries in a Claude Code
.mcp.json-style file, preserving every other key.

Usage:
    merge_mcp_json.py <json_path> <vault_dir> [--remove]

Exit codes: 0 ok, 1 unexpected error, 2 existing file is invalid JSON.
"""
import json
import os
import sys

MANAGED_SERVERS = ("second-brain", "basic-memory")


def managed_entries(vault_dir: str) -> dict:
    return {
        "second-brain": {
            "command": os.path.join(vault_dir, "70-scripts", "mcp", "second-brain-mcp"),
            "args": [],
        },
        "basic-memory": {
            "command": "uvx",
            "args": ["basic-memory", "mcp"],
        },
    }


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 1
    path, vault_dir = sys.argv[1], sys.argv[2]
    remove = "--remove" in sys.argv[3:]

    data: dict = {}
    if os.path.exists(path):
        try:
            with open(path) as f:
                data = json.load(f)
        except json.JSONDecodeError as exc:
            print(f"refusing to modify invalid JSON in {path}: {exc}", file=sys.stderr)
            return 2
        if not isinstance(data, dict):
            print(f"refusing to modify {path}: top level is not an object", file=sys.stderr)
            return 2

    servers = data.setdefault("mcpServers", {})
    if remove:
        for name in MANAGED_SERVERS:
            servers.pop(name, None)
        if not servers:
            data.pop("mcpServers", None)
    else:
        servers.update(managed_entries(vault_dir))

    tmp = path + ".tmp"
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    # Self-check before replacing.
    with open(tmp) as f:
        json.load(f)
    os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
