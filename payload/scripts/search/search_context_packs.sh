#!/usr/bin/env bash
# search over generated context packs (spec §13.1 context-packs collection).
exec "$(cd "$(dirname "$0")" && pwd)/sb_search.sh" --collection context-packs "$@"
