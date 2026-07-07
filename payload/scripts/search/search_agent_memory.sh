#!/usr/bin/env bash
# search_agent_memory(query, project, memory_type, max_results) — spec §10.1.
exec "$(cd "$(dirname "$0")" && pwd)/sb_search.sh" --collection core-memory "$@"
