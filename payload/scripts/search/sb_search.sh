#!/usr/bin/env bash
# sb_search.sh — stable shell entry point for scoped vault search.
# All arguments are forwarded to sb_search.py; see --help there.
set -u
. "$(cd "$(dirname "$0")" && pwd)/../lib/sb_common.sh"
exec "$(sb_python_bin)" "$SB_SCRIPTS_ROOT/search/sb_search.py" "$@"
