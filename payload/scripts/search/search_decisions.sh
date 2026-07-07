#!/usr/bin/env bash
# search_decisions(query, project, status, max_results) — spec §10.1.
exec "$(cd "$(dirname "$0")" && pwd)/sb_search.sh" --collection decisions "$@"
