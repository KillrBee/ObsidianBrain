#!/usr/bin/env bash
# search_sources(query, project, source_type, date_range, max_results) — spec §10.1.
exec "$(cd "$(dirname "$0")" && pwd)/sb_search.sh" --collection sources-converted "$@"
