#!/usr/bin/env bash
# remember.sh — write agent memory from any environment (script-mode parity
# with the MCP memory tools: same dedup guard and unreviewed stamping).
#
#   remember.sh observe "Entity Name" "what was learned" --confidence high
#   remember.sh relate "Entity A" depends_on "Entity B"
#   remember.sh note 40-agent-memory/observations/topic.md "content" [--force]
#   remember.sh review 40-agent-memory/observations/topic.md
set -u
. "$(cd "$(dirname "$0")" && pwd)/../lib/sb_common.sh"
exec "$(sb_python_bin)" "$SB_SCRIPTS_ROOT/memory/sb_memory.py" "$@"
