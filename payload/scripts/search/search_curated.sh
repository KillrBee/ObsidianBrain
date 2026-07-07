#!/usr/bin/env bash
# search_curated(query, project, domain, status, max_results) — spec §10.1.
exec "$(cd "$(dirname "$0")" && pwd)/sb_search.sh" --collection curated "$@"
