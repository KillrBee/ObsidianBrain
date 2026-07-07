#!/usr/bin/env bash
# reconvert_document.sh — force reconversion of one original, preserving the
# manifest history entry (spec §10.5 reconvert_document).
#
# Usage: reconvert_document.sh [--vault DIR] <path-to-original>

set -u
. "$(cd "$(dirname "$0")" && pwd)/../lib/sb_common.sh"

SOURCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) SB_VAULT_ROOT="${2:?--vault needs a value}"; shift ;;
    --vault=*) SB_VAULT_ROOT="${1#*=}" ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) SOURCE="$1" ;;
  esac
  shift
done
sb_require_vault
[ -n "$SOURCE" ] || { sb_err "usage: reconvert_document.sh [--vault DIR] <path>"; exit 64; }

exec "$(sb_python_bin)" "$SB_SCRIPTS_ROOT/convert/convert_one.py" \
  --vault "$SB_VAULT_ROOT" --source "$SOURCE" --force
